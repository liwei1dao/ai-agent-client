package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
	"sort"
	"strings"
	"time"
)

// RebuildStats 全量重建 App 综合统计（仅超管）
//
// 清空 app_stat_daily/monthly/yearly/global 后，从以下源表全量重算：
//   - payorder：order_count(create_time)、failed_order_count(create_time, status=FAILED)、
//     pay_amount/pay_count/pay_user_count(pay_time, status=PAID)
//   - user：new_user_count(createtime)
//   - useruselog：add_vip_days/add_ai_integral/add_trade_second/add_meet_second(ts)
//   - userstatistics（仅 global 行）：ai/trade/meet 累计消耗
//   - userdevice（仅 global 行）：bind_device_count
//
// 无法重建的字段（无历史时间戳/审计）将留 0：
//
//	login_count、active_user_count、active_device_count；
//	ai_chat/trade/meet 消耗的日/月/年分布（只能汇总到 global 行）。
//
// @Summary 重建统计数据
// @Description 清空并从源表重算 App 综合统计（仅超管）
// @Tags API
// @Accept json
// @Produce json
// @Param user body pb.ApiRebuildStatsReq true "重建请求"
// @Success 200 {object} comm.HttpResult{data=pb.ApiRebuildStatsResp} "成功"
// @Router /web/api/api_rebuildstats [post]
func (this *apiComp) RebuildStats(session comm.IUserSession, req *pb.ApiRebuildStatsReq) (resp *pb.ApiRebuildStatsResp, errdata *pb.ErrorData) {
	start := time.Now()
	resp = &pb.ApiRebuildStatsResp{}

	// 0. 先从消耗日志重建 userstatistics（排行榜 + 后续 global 汇总均依赖此表）
	uRows, uErr := this.module.model.rebuildUserStatisticsFromLogs()
	if uErr != nil {
		errdata = dbErr(uErr, "rebuildUserStatisticsFromLogs")
		return
	}
	this.module.Info("RebuildStats: userstatistics rebuilt from logs",
		log.Field{Key: "rows", Value: uRows},
	)

	// 1. 各源表分组聚合（DB 端 GROUP BY，避免拉全表到 Go）
	orderCreate, err := this.module.model.aggOrderCreate()
	if err != nil {
		errdata = dbErr(err, "aggOrderCreate")
		return
	}
	orderFailed, err := this.module.model.aggOrderFailed()
	if err != nil {
		errdata = dbErr(err, "aggOrderFailed")
		return
	}
	orderPaid, err := this.module.model.aggOrderPaid()
	if err != nil {
		errdata = dbErr(err, "aggOrderPaid")
		return
	}
	userSignup, err := this.module.model.aggUserSignup()
	if err != nil {
		errdata = dbErr(err, "aggUserSignup")
		return
	}
	useLog, err := this.module.model.aggUseLogGrant()
	if err != nil {
		errdata = dbErr(err, "aggUseLogGrant")
		return
	}

	// 2. 合并到 daily map（key=YYYY-MM-DD）
	daily := make(map[string]*pb.DBAppStat)
	getOrInit := func(d string) *pb.DBAppStat {
		row, ok := daily[d]
		if !ok {
			row = &pb.DBAppStat{StatDate: d}
			daily[d] = row
		}
		return row
	}
	for _, r := range orderCreate {
		getOrInit(r.D).OrderCount += int32(r.Count)
	}
	for _, r := range orderFailed {
		getOrInit(r.D).FailedOrderCount += int32(r.Count)
	}
	for _, r := range orderPaid {
		row := getOrInit(r.D)
		row.PayAmount += r.Amount
		row.PayCount += int32(r.Count)
		row.PayUserCount += int32(r.UserCount)
	}
	for _, r := range userSignup {
		getOrInit(r.D).NewUserCount += int32(r.Count)
	}
	for _, r := range useLog {
		row := getOrInit(r.D)
		row.AddVipDays += r.AddVipDay
		row.AddAiIntegral += r.AddAgentInt
		row.AddTradeSecond += r.AddTradeSec
		row.AddMeetSecond += r.AddMeetSec
	}

	// 3. 按日期排序，并累计 total_user_count 快照
	dailyRows := make([]*pb.DBAppStat, 0, len(daily))
	for _, r := range daily {
		dailyRows = append(dailyRows, r)
	}
	sort.Slice(dailyRows, func(i, j int) bool { return dailyRows[i].StatDate < dailyRows[j].StatDate })
	var cumUser int64
	now := time.Now().Unix()
	for _, r := range dailyRows {
		cumUser += int64(r.NewUserCount)
		r.TotalUserCount = cumUser
		r.UpdateTime = now
	}

	// 4. 月 / 年汇总（基于已修正 total_user_count 的日行；快照字段取该期末值）
	monthlyRows := rollupByPrefix(dailyRows, 7) // YYYY-MM
	yearlyRows := rollupByPrefix(dailyRows, 4)  // YYYY

	// 5. global 行：日聚合无法覆盖的字段从生命周期 SQL 单独取
	gPayAmount, gPayCount, gPayUserCount, gOrderCount, gFailedCount, err := this.module.model.sumLifetimePayments()
	if err != nil {
		errdata = dbErr(err, "sumLifetimePayments")
		return
	}
	gVipDay, gAiInt, gTradeSec, gMeetSec, err2 := this.module.model.sumLifetimeUseLog()
	if err2 != nil {
		errdata = dbErr(err2, "sumLifetimeUseLog")
		return
	}
	gAiChat, gAiUp, gAiDown, gTradeCount, gTradeTime, gTradeWords, gMeetCount, gMeetTime, err3 := this.module.model.sumLifetimeUserStats()
	if err3 != nil {
		errdata = dbErr(err3, "sumLifetimeUserStats")
		return
	}
	gTotalUsers, err := this.module.model.countTotalUsers()
	if err != nil {
		errdata = dbErr(err, "countTotalUsers")
		return
	}
	gDevices, err := this.module.model.countUserDevices()
	if err != nil {
		errdata = dbErr(err, "countUserDevices")
		return
	}
	gVipUsers, err := this.module.model.countActiveVipUsers(now)
	if err != nil {
		errdata = dbErr(err, "countActiveVipUsers")
		return
	}

	global := &pb.DBAppStat{
		StatDate:         GlobalStatDate,
		PayAmount:        gPayAmount,
		OrderCount:       int32(gOrderCount),
		PayCount:         int32(gPayCount),
		FailedOrderCount: int32(gFailedCount),
		PayUserCount:     int32(gPayUserCount),
		AddVipDays:       gVipDay,
		AddAiIntegral:    gAiInt,
		AddTradeSecond:   gTradeSec,
		AddMeetSecond:    gMeetSec,
		AiChatCount:      gAiChat,
		AiUpToken:        gAiUp,
		AiDownToken:      gAiDown,
		TradeCount:       gTradeCount,
		TradeTime:        gTradeTime,
		TradeWords:       gTradeWords,
		MeetCount:        gMeetCount,
		MeetTime:         gMeetTime,
		NewUserCount:     int32(gTotalUsers),
		TotalUserCount:   gTotalUsers,
		VipUserCount:     int32(gVipUsers),
		BindDeviceCount:  int32(gDevices),
		UpdateTime:       now,
	}

	// 6. 原子改写：在 stat consumer 锁内 TRUNCATE + INSERT + ReloadCache，
	//    避免消费者拿着旧的内存缓存覆盖刚重建的数据。
	werr := this.module.statConsumer.WithLock(func() error {
		if e := this.module.model.truncateStatTables(); e != nil {
			return e
		}
		if e := this.module.model.insertStatRows(comm.TableAppStatDaily, dailyRows); e != nil {
			return e
		}
		if e := this.module.model.insertStatRows(comm.TableAppStatMonthly, monthlyRows); e != nil {
			return e
		}
		if e := this.module.model.insertStatRows(comm.TableAppStatYearly, yearlyRows); e != nil {
			return e
		}
		if e := this.module.model.insertStatRows(comm.TableAppStatGlobal, []*pb.DBAppStat{global}); e != nil {
			return e
		}
		// 仍在锁内：直接刷新 consumer 内存缓存
		this.module.statConsumer.loadCache(time.Now())
		return nil
	})
	if werr != nil {
		errdata = dbErr(werr, "rebuild atomic")
		return
	}

	// 7. 重建产品激活/绑定统计：全量扫描 userdevice 落库 product_stat，
	//    供代理仪表盘（api_getagentdashboard）按产品读取激活数 / 绑定用户数。
	psRows, psErr := this.module.model.rebuildProductStats()
	if psErr != nil {
		errdata = dbErr(psErr, "rebuildProductStats")
		return
	}
	this.module.Info("RebuildStats: product_stat rebuilt",
		log.Field{Key: "rows", Value: psRows},
	)

	resp.DailyRows = int32(len(dailyRows))
	resp.MonthlyRows = int32(len(monthlyRows))
	resp.YearlyRows = int32(len(yearlyRows))
	resp.CostMs = time.Since(start).Milliseconds()

	this.module.Info("RebuildStats done",
		log.Field{Key: "daily", Value: resp.DailyRows},
		log.Field{Key: "monthly", Value: resp.MonthlyRows},
		log.Field{Key: "yearly", Value: resp.YearlyRows},
		log.Field{Key: "cost_ms", Value: resp.CostMs},
	)
	return
}

// rollupByPrefix 把 daily 行按日期前缀 (7=YYYY-MM, 4=YYYY) 聚合成月/年行。
// 快照字段 total_user_count 取该期内最大值（= 期末累计用户数）。
func rollupByPrefix(daily []*pb.DBAppStat, prefixLen int) []*pb.DBAppStat {
	bucket := make(map[string]*pb.DBAppStat)
	for _, d := range daily {
		if len(d.StatDate) < prefixLen {
			continue
		}
		key := d.StatDate[:prefixLen]
		row, ok := bucket[key]
		if !ok {
			row = &pb.DBAppStat{StatDate: key, UpdateTime: d.UpdateTime}
			bucket[key] = row
		}
		row.PayAmount += d.PayAmount
		row.OrderCount += d.OrderCount
		row.PayCount += d.PayCount
		row.FailedOrderCount += d.FailedOrderCount
		row.PayUserCount += d.PayUserCount
		row.AddVipDays += d.AddVipDays
		row.AddAiIntegral += d.AddAiIntegral
		row.AddTradeSecond += d.AddTradeSecond
		row.AddMeetSecond += d.AddMeetSecond
		row.NewUserCount += d.NewUserCount
		if d.TotalUserCount > row.TotalUserCount {
			row.TotalUserCount = d.TotalUserCount
		}
	}
	out := make([]*pb.DBAppStat, 0, len(bucket))
	for _, r := range bucket {
		out = append(out, r)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].StatDate < out[j].StatDate })
	return out
}

func dbErr(err error, where string) *pb.ErrorData {
	return &pb.ErrorData{
		Code:    pb.ErrorCode_DBError,
		Message: where + ": " + strings.TrimSpace(err.Error()),
	}
}
