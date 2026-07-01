package comm

// NATS 管道统一定义。
//
// 跨服务的各类消息管道（subject / 事件结构）集中在此，便于统一管理与后续扩展——
// 新增管道在本文件追加，避免 subject 魔法字符串散落各处。
//
// 两种语义按需选用：
//   - JetStream（持久、可回放、消费者可负载均衡）：用于不能丢的数据流，如统计上报。
//     发布走 natssys.Publish/PublishAsync，订阅走 JetStream 持久消费者。
//   - core NATS pub/sub（至多一次、fanout 到所有订阅者）：用于广播类通知，如配置变更。
//     发布/订阅走 natssys.Conn().Publish / Conn().Subscribe。

const (
	// Nats_StatEventSubject 统计上报管道（JetStream）：各业务部署 analyze 把埋点事件双写到此，
	// console 消费落 stats_global_day。作为 canonical 名称；yaml(modules.analyze.Subject /
	// modules.console.Stat.Subject) 配置应与之一致。
	Nats_StatEventSubject = "stats.event"

	// Nats_ConfigChangedSubject 配置变更广播（core NATS pub/sub）：console 后台改了「全局共享配置」
	// (全局环境配置/MCP/会议模板) 后向此 subject 广播；各业务服务订阅后重载对应缓存。
	// 广播语义——所有订阅者都收到；漏收由业务侧 10 分钟定时同步兜底。
	Nats_ConfigChangedSubject = "console.config.changed"

	// Nats_ConfigEventSubjectPrefix 按「单个应用」下发配置事件的 subject 前缀（JetStream）。
	// 实际 subject 以注册项 nats_subject 字段为准，留空时回退到 "<前缀><appId>"。
	Nats_ConfigEventSubjectPrefix = "console.config."
)

// 配置变更类型（ConfigChangedEvent.Kind 取值）：业务侧据此重载对应缓存。
const (
	ConfigKindGlobalConfig  = "global_config" // 全局第三方服务配置（user 模块重载）
	ConfigKindMcp           = "mcp"           // MCP 服务器（user 模块重载）
	ConfigKindTemplate      = "template"      // 会议公共模板（echomeet 模块重载）
	ConfigKindThirdSvc      = "third_svc"     // 依赖服务配置（业务侧重载字段缓存）
	ConfigKindCallTranslate = "call_translate" // 通话翻译配置（translate 模块重载）
)

// ConfigChangedEvent console→业务 的「配置已变更」广播事件。
// 业务服务订阅 Nats_ConfigChangedSubject，收到后按 Kind 重载对应缓存。
type ConfigChangedEvent struct {
	Kind   string `json:"kind"`   // 变更的配置类型，见 ConfigKind*
	Action string `json:"action"` // add / update / delete
	Region int32  `json:"region"` // 关联区域(global_config/mcp 带；template 为 0)
	Ts     int64  `json:"ts"`     // 发出时间戳（秒）
}
