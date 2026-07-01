package api

import (
	"context"
	"yunyan/comm"
	"yunyan/lego/core"
	"yunyan/lego/core/cbase"
	"yunyan/lego/sys/log"
	"yunyan/lego/sys/mysql"
	redissys "yunyan/lego/sys/redis"
	"yunyan/pb"
	"yunyan/sys/appstat"
	"encoding/json"
	"sync"
	"time"
)

// statConsumerComp 消费 Redis 统计队列并写入日/月/年三张 DB 表。
// 内存中缓存当前日/月/年三行数据，启动时从 DB 加载一次；
// 每次 flush 在内存累加后立即写入 DB，日期切换时加载新行。
type statConsumerComp struct {
	cbase.ModuleCompBase
	module *API
	cancel context.CancelFunc

	// 内存缓存（三个时间粒度 + 全局累计）
	// mu 保护以下四个缓存指针的读写，避免 consumer flush 与外部全量重建并发改写。
	mu      sync.Mutex
	daily   *pb.DBAppStat
	monthly *pb.DBAppStat
	yearly  *pb.DBAppStat
	global  *pb.DBAppStat
}

// 全局累计行固定 stat_date 标识
const GlobalStatDate = "all"

func (this *statConsumerComp) Init(service core.IService, module core.IModule, comp core.IModuleComp, opt core.IModuleOptions) (err error) {
	this.ModuleCompBase.Init(service, module, comp, opt)
	this.module = module.(*API)
	return
}

func (this *statConsumerComp) Start() (err error) {
	if err = this.ModuleCompBase.Start(); err != nil {
		return
	}
	// 启动时从 DB 加载当前日/月/年缓存行
	this.loadCache(time.Now())

	ctx, cancel := context.WithCancel(context.Background())
	this.cancel = cancel
	go this.consume(ctx)
	log.Infoln("appstat consumer started")
	return
}

func (this *statConsumerComp) Destroy() (err error) {
	if this.cancel != nil {
		this.cancel()
	}
	return this.ModuleCompBase.Destroy()
}

// loadCache 从 DB 加载指定时间点对应的日/月/年/全局行（不存在则初始化空行）
func (this *statConsumerComp) loadCache(t time.Time) {
	this.daily = this.loadOrNew(comm.TableAppStatDaily, t.Format("2006-01-02"))
	this.monthly = this.loadOrNew(comm.TableAppStatMonthly, t.Format("2006-01"))
	this.yearly = this.loadOrNew(comm.TableAppStatYearly, t.Format("2006"))
	this.global = this.loadOrNew(comm.TableAppStatGlobal, GlobalStatDate)
}

func (this *statConsumerComp) loadOrNew(tbl, date string) *pb.DBAppStat {
	var row pb.DBAppStat
	if err := mysql.FindOne(tbl, &row, "stat_date=?", date); err != nil {
		row = pb.DBAppStat{StatDate: date}
	}
	return &row
}

// consume 从 Redis 队列消费统计增量
func (this *statConsumerComp) consume(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		default:
		}
		vals, err := redissys.Conn().BRPop(ctx, 5*time.Second, redissys.RKey(appstat.RedisQueueKey)).Result()
		if err != nil {
			continue
		}
		if len(vals) < 2 {
			continue
		}
		var delta pb.DBAppStat
		if err = json.Unmarshal([]byte(vals[1]), &delta); err != nil {
			this.module.Warn("stat consumer unmarshal", log.Field{Key: "err", Value: err.Error()})
			continue
		}
		this.flush(&delta)
	}
}

// checkExpired 各粒度独立检查是否过期，过期则创建新的空统计对象；全局行不过期
func (this *statConsumerComp) checkExpired(now time.Time) {
	if today := now.Format("2006-01-02"); this.daily == nil || this.daily.StatDate != today {
		this.daily = &pb.DBAppStat{StatDate: today}
	}
	if month := now.Format("2006-01"); this.monthly == nil || this.monthly.StatDate != month {
		this.monthly = &pb.DBAppStat{StatDate: month}
	}
	if year := now.Format("2006"); this.yearly == nil || this.yearly.StatDate != year {
		this.yearly = &pb.DBAppStat{StatDate: year}
	}
	if this.global == nil {
		this.global = this.loadOrNew(comm.TableAppStatGlobal, GlobalStatDate)
	}
}

// flush 将 delta 累加到内存缓存后立即写入 DB
func (this *statConsumerComp) flush(delta *pb.DBAppStat) {
	if len(delta.StatDate) < 10 {
		this.module.Warn("stat consumer flush: invalid StatDate", log.Field{Key: "date", Value: delta.StatDate})
		return
	}
	this.mu.Lock()
	defer this.mu.Unlock()
	this.checkExpired(time.Now())

	accum(this.daily, delta)
	accum(this.monthly, delta)
	accum(this.yearly, delta)
	accum(this.global, delta)

	this.saveRow(comm.TableAppStatDaily, this.daily)
	this.saveRow(comm.TableAppStatMonthly, this.monthly)
	this.saveRow(comm.TableAppStatYearly, this.yearly)
	this.saveRow(comm.TableAppStatGlobal, this.global)
}

// ReloadCache 由外部（如全量重建）在改写 DB 后调用，丢弃过期内存缓存重新从 DB 加载。
func (this *statConsumerComp) ReloadCache() {
	this.mu.Lock()
	defer this.mu.Unlock()
	this.loadCache(time.Now())
}

// WithLock 提供给外部对四张统计表执行原子改写（清空+重建）使用，
// 期间 consumer flush 被阻塞，避免被半成品状态覆盖。
func (this *statConsumerComp) WithLock(fn func() error) error {
	this.mu.Lock()
	defer this.mu.Unlock()
	return fn()
}

func (this *statConsumerComp) saveRow(tbl string, row *pb.DBAppStat) {
	if row == nil {
		return
	}
	row.UpdateTime = time.Now().Unix()
	if err := mysql.Save(tbl, row); err != nil {
		this.module.Warn("stat consumer save", log.Field{Key: "table", Value: tbl}, log.Field{Key: "err", Value: err.Error()})
	}
}

// accum 将 delta 各字段累加到 row 上
func accum(row, delta *pb.DBAppStat) {
	row.PayAmount += delta.PayAmount
	row.OrderCount += delta.OrderCount
	row.PayCount += delta.PayCount
	row.FailedOrderCount += delta.FailedOrderCount
	row.PayUserCount += delta.PayUserCount
	row.AddVipDays += delta.AddVipDays
	row.AddAiIntegral += delta.AddAiIntegral
	row.AddTradeSecond += delta.AddTradeSecond
	row.AddMeetSecond += delta.AddMeetSecond
	row.AiChatCount += delta.AiChatCount
	row.AiUpToken += delta.AiUpToken
	row.AiDownToken += delta.AiDownToken
	row.TradeCount += delta.TradeCount
	row.TradeTime += delta.TradeTime
	row.TradeWords += delta.TradeWords
	row.MeetCount += delta.MeetCount
	row.MeetTime += delta.MeetTime
	row.NewUserCount += delta.NewUserCount
	row.LoginCount += delta.LoginCount
	row.ActiveUserCount += delta.ActiveUserCount
	row.TotalUserCount = delta.TotalUserCount // 快照值，直接覆盖
	row.VipUserCount += delta.VipUserCount
	row.BindDeviceCount += delta.BindDeviceCount
	row.ActiveDeviceCount += delta.ActiveDeviceCount
}
