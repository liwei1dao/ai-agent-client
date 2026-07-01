package comm

import "yunyan/pb"

// 本文件集中定义「模块对外接口」。
//
// 一个模块若要把能力开放给其它模块调用，在此定义一个接口；目标模块的实现类型
// 实现该接口即可。调用方在启动阶段通过 service.GetModule(模块名) 取到模块实例，
// 断言为对应接口后调用——业务模块之间因此无需直接 import 对方的包。

// ===================== 统计模块 analyze =====================

// StatEventType 埋点事件类型。
type StatEventType int32

const (
	StatEventUnknown       StatEventType = 0
	StatEventLogin         StatEventType = 1  // 用户登录
	StatEventRegister      StatEventType = 2  // 新用户注册
	StatEventDeviceActive  StatEventType = 3  // 设备激活
	StatEventDeviceBind    StatEventType = 4  // 设备绑定账号
	StatEventOrderCreate   StatEventType = 5  // 创建订单
	StatEventOrderPaid     StatEventType = 6  // 订单支付完成
	StatEventOrderFailed   StatEventType = 7  // 订单失败
	StatEventTranslate     StatEventType = 8  // 翻译使用
	StatEventMeeting       StatEventType = 9  // 会议使用
	StatEventAiChat        StatEventType = 10 // AI 聊天
	StatEventResourceGrant StatEventType = 11 // 资源发放
	StatEventQRCodeActive  StatEventType = 12 // 二维码(公码)激活：用户扫公码领奖成功一次计一次
)

// StatEvent 统一埋点对象：业务模块通过 IAnalyze.Report 投递，一个对象走天下，
// 靠 Type 区分语义，公共数值字段按需填写。
type StatEvent struct {
	Type      StatEventType
	ProductId uint32 // 产品ID：设备类事件填设备产品；订单/发放/消耗类事件填用户最后绑定产品(DBUser.Lastbindproductid)；无绑定填 0
	Uid       string // 触发用户；用于登录/活跃/付费用户的去重统计

	Count   int64 // 通用次数，<=0 时按 1 计
	Amount  int64 // 金额(分)：订单类事件
	Second  int64 // 时长(秒)：翻译 / 会议
	Words   int64 // 字数：翻译
	UpToken int64 // 上行 token：AI
	DnToken int64 // 下行 token：AI

	// 资源发放（StatEventResourceGrant）
	GrantVipDay      int64
	GrantAiIntegral  int64
	GrantTradeSecond int64
	GrantMeetSecond  int64
}

// StatSnapshotKind 是 StatSnapshot.Kind 的固定取值，供消费端识别快照消息、
// 区分（并丢弃）管道里可能残留的历史逐事件消息。
const StatSnapshotKind = "snapshot"

// StatSnapshot 是业务侧 analyze 推送到 NATS 统计管道的「当日某分区绝对快照」
// （发送端 analyze 与 console 统计消费端共享）。
//
// 设计：业务侧 analyze 始终把埋点实时累加到本地 Redis（崩溃不丢）；同步器在【启动时 / 每个
// 同步周期 / 0 点】把 Redis 里 app×region×product×day 各分区的【当日绝对聚合】打包成本结构推送。
// console 收到后直接以绝对值覆盖 upsert 到 stats_global_day——
//   - 绝对值幂等：重复/乱序投递、重启重放都收敛到最新值，不会重复计数；
//   - 自愈：偶发丢消息由下一次快照补回，业务重启时的启动快照即完成对账；
//   - 去重人数(HLL)在业务侧本地算好，随 Row.*UserCount 以整数带过来，console 不再维护 HLL。
//
// Row 即一行 stats_global_day（含复合主键维度 app_id/region/product_id/stat_day 与全部指标），
// 直接复用以避免维度/字段两处定义漂移。Row.AppId 须与 console 注册表中的应用名称完全一致，
// 否则 console 视为未注册、不落库。
type StatSnapshot struct {
	Kind string             `json:"kind"` // 固定 StatSnapshotKind
	Ts   int64              `json:"ts"`   // 快照生成时间(unix 秒)；与接收时间差大=迟到
	Row  *pb.StatsGlobalDay `json:"row"`  // 该分区当日绝对聚合，直接落 stats_global_day
}

// IAnalyze 是统计模块 analyze 对外暴露的埋点接口。
//
// 用法：业务模块在 Start 阶段获取并缓存——
//
//	if m, err := service.GetModule(comm.ModuleAnalyze); err == nil {
//	    this.analyze, _ = m.(comm.IAnalyze)
//	}
//
// 之后在业务流程中调用 this.analyze.Report(...) 投递埋点（注意判空）。
type IAnalyze interface {
	// Report 投递一个埋点事件。非阻塞，失败即丢弃，不阻断业务主流程。
	Report(e *StatEvent)
}
