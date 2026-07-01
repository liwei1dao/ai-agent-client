package comm

import "yunyan/lego/core"

// 服务定义
const (
	Service_Gateway = "gateway" //网关服务 可多开
	Service_Home    = "home"    //大厅服务 运行一些公用接口
	Service_Api     = "api"     //渠道接口服
	Service_Migu    = "migu"    //移动灵犀聊天服务 独立部署 对外OpenAI兼容接口
	Service_Console = "console" //后台控制面服务 独立部署 注册各应用 直连应用库 + 发配置事件
)

// 服务组件名称
const (
	SC_ServiceHttpRouteComp core.S_Comps = "SC_HttpRouteComp" //服务组件 消息路由组件
)

// 模块名定义处
const (
	ModuleGate     core.M_Modules = "gateway"  //gate模块 网关服务模块
	ModuleApi      core.M_Modules = "api"      //gate模块 网关服务模块
	ModuleUser     core.M_Modules = "user"     //gate模块 网关服务模块
	ModuleAuth     core.M_Modules = "auth"     //gate模块 网关服务模块
	ModuleChat     core.M_Modules = "chat"     //chat模块 聊天服务模块
	ModuleAgents   core.M_Modules = "agents"   //agenfts模块 智能体模块
	ModuleMcp      core.M_Modules = "mcp"      //gate模块 网关服务模块
	ModuleMusic    core.M_Modules = "music"    //gate模块 网关服务模块
	ModuleAitools  core.M_Modules = "aitools"  //gate模块 网关服务模块
	ModuleEchomeet core.M_Modules = "echomeet" //会议记录模块
	ModulePay      core.M_Modules = "pay"      //gate模块 网关服务模块
	ModuleTimer    core.M_Modules = "timer"    //gate模块 网关服务模块
	ModuleAllhelp  core.M_Modules = "allhelp"  //万能助理模块 定时提醒任务 + 每日聊天总结
	ModuleBailian  core.M_Modules = "bailian"  //百炼设备计量中转模块（半托管License）
	ModuleMigu     core.M_Modules = "migu"     //移动灵犀聊天模块 对外OpenAI兼容接口 内部调咪咕灵犀
	ModuleAnalyze  core.M_Modules = "analyze"  //埋点分析模块 业务侧经 GetModule 取用 上报统计事件
	ModuleConsole  core.M_Modules = "console"  //后台控制面模块 注册各应用+按应用建连+发配置事件
)

const (
	Rpc_GatewayHttpRoute core.Rpc_Key = "Rpc_GatewayHttpRoute" //Http网关路由
)

// 数据表名定义处
const (
	TableUser             = "user"              //用户表
	TableUserdevice       = "userdevice"        //用户设备列表
	TableRecord           = "record"            //记录表
	TableAgent            = "agent"             //智能体id
	TableMcp              = "mcp"               //Mcp服务
	TableAppConfig        = "config"            //App自有配置（音乐、OSS等）
	TableGlobalConfig     = "global_config"     //全局第三方服务配置（AI、翻译等，按区域）
	TableAdmin            = "adnim"             //后台用户表
	TableEchomeetTemplate = "echomeet_template" //模板表
	TableEchomeetRecord   = "echomeet_record"   //会议记录表

	TableChannelApp          = "channelapp"           //渠道包管理
	TableFactory             = "factory"              //厂商数据表
	TableProduct             = "product"              //产品表
	TableProductVersion      = "product_version"      //产品表版本管理
	TableFactoryDeliveryNote = "factory_deliverynote" //厂家出货日志表
	TableLicense             = "license"              //授权码表
	TableGoods               = "goods"                //支付商品表
	TablePayOrder            = "payorder"             //支付订单表
	TableWakeupVoice         = "wakeupvoice"          //唤醒语音表
	TableUserUseLog          = "useruselog"           //用户日志
	TableUserStatistics      = "userstatistics"       //用户统计表

	// TableAuthCode            = "authcode"             //授权码表
	// TableFactoryDevice = "factorydevice" //厂家设备表

	TableUseRecordLog      = "uselog"              //用户使用统计日志
	TableAppStatDaily      = "app_stat_daily"      //App综合统计-日表
	TableAppStatMonthly    = "app_stat_monthly"    //App综合统计-月表
	TableAppStatYearly     = "app_stat_yearly"     //App综合统计-年表
	TableAppStatGlobal     = "app_stat_global"     //App综合统计-全局累计(单行 stat_date=all)
	TableConsoleLog        = "console_log"         //后台操作日志表
	TableAdminResLog       = "admin_resource_log"  //后台账号资源流水（超管→管理员/代理/运营）
	TableAllhelpTask       = "allhelp_task"        //用户定时提醒任务表
	TableChatSummary       = "chat_summary"        //用户每日聊天总结表
	TableStatsGlobalDay    = "stats_global_day"    //平台每日统计表（应用×产品×区域×日）
	TableProductStat       = "product_stat"        //产品激活/绑定统计表（重建统计时全量扫描 userdevice 落库）
	TableFactoryPublicCode = "factory_public_code" //厂家公码表（一厂家多码，新用户扫码领奖，user.isgiveaway 判重）
	TableAppRegistry       = "app_registry"        //应用注册表（console 独立库，存各应用地址/双DSN/Redis/前缀/NATS事件通道）
	TableConsoleAccount    = "console_account"     //后台账号表（console 独立库，存账号/bcrypt密码/角色）

	TableThirdSvcConfig         = "third_svc_config"          //依赖服务配置表（JSONB 字段定义 + 默认值，移植自 deep_server）
	TableThirdSvcRegionOverride = "third_svc_region_override" //依赖服务区域字段覆盖表（每服务×区域一行，JSONB map）
	TableCallTranslatePair      = "call_translate_pair"       //通话翻译语言对配置表（区域×语言对×服务编排）
)

// NATS 管道 subject 与事件结构统一定义在 comm/nats.go（含 Nats_ConfigEventSubjectPrefix 等）。

// 对象池定义
const (
	Pool_UserSession = "Pool_UserSession" //对象此 comm.UserSession
)

// 对象池定义
const (
	Redis_Verification = "Verification" //验证码
)

// 缓存数据集名定义（实际 Redis key 经 redissys.RKey 加应用前缀）
const (
	Cache_Product          = "cache:product"           //product 全量缓存（Redis Hash，field=id）
	Cache_EchomeetTemplate = "cache:echomeet_template" //echomeet public 公共模板全量缓存（Redis Hash，field=id）
)

// RPC服务接口定义处
const ( //Rpc
	Rpc_ModifyAppConifg        core.Rpc_Key = "Rpc_ModifyAppConifg"        //修改app配置
	Rpc_ModifyEchomeetTemplate core.Rpc_Key = "Rpc_ModifyEchomeetTemplate" //修改echomeet公共模板
)
