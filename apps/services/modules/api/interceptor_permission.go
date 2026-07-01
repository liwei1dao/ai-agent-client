package api

import (
	"strings"

	"yunyan/comm"
	"yunyan/lego/core"
	"yunyan/lego/core/cbase"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// 接口授权语义
const (
	scopeNone  = "*none"  // 无需登录
	scopeAdmin = "*admin" // 仅站长
	scopeAny   = "*any"   // 已登录任意身份均可（工具类接口，无对应页面）
	scopeAgent = "*agent" // 仅代理身份（identity=3）
)

// apiPageMap 接口 -> 后台页面 id（与 console/admin.html 中 scopedPages 对齐）
// 取值含义：
//   - 页面 id（dashboard/factory/...）：Admin/Manager 直通；Agent/Operator 需在 access 中勾选
//   - scopeNone：完全开放
//   - scopeAdmin：仅 Admin
//   - scopeAny：登录后任意身份可访问（无页面归属的工具类接口）
var apiPageMap = map[string]string{
	// === 无需登录 ===
	"api_login":       scopeNone,
	"api_getsiteinfo": scopeNone,

	// === 仅站长（账号管理） ===
	"api_addadminuser":       scopeAdmin,
	"api_deladminuser":       scopeAdmin,
	"api_updateadminuser":    scopeAdmin,
	"api_getadminusers":      scopeAdmin,
	"api_grantadminresource": scopeAdmin, // 超管→后台账号 资源点赠送

	// === dashboard 仪表盘 ===
	"api_getglobalstats": "dashboard",
	"api_rebuildstats":   scopeAdmin, // 全量重建统计（清空+全库重算，仅超管）

	// === factory 厂家管理 ===
	"api_getfactory":              "factory",
	"api_getfactorys":             "factory",
	"api_addfactory":              "factory",
	"api_updatefactory":           "factory",
	"api_delfactory":              "factory",
	"api_getfactorypubliccodes":   "factory",
	"api_createfactorypubliccode": "factory",
	"api_updatefactorypubliccode": "factory",
	"api_delfactorypubliccode":    "factory",

	// === product 产品管理 ===
	"api_getproduct":         "product",
	"api_getproducts":        "product",
	"api_getproductversions": "product",
	"api_addproduct":         "product",
	"api_updateproduct":      "product",
	"api_delproduct":         "product",
	"api_addproductversion":  "product",
	"api_delproductversion":  "product",

	// === device 生产管理 ===
	"api_getfactorydevic":         "device",
	"api_getfactorydevics":        "device",
	"api_createfactorydevics":     "device",
	"api_restfactorydevics":       "device",
	"api_resetlicensestatus":      "device",
	"api_getauthcode":             "device",
	"api_getauthcodes":            "device",
	"api_createauthcode":          "device",
	"api_getfactorydeliverynotes": "device",
	"api_revokefactorydevics":     scopeAdmin, // 撤销生产批次，仅超管

	// === goods 商品管理 ===
	"api_getgoods":    "goods",
	"api_getgoodss":   "goods",
	"api_addgoods":    "goods",
	"api_updategoods": "goods",
	"api_delgoods":    "goods",

	// === order 订单查询 ===
	"api_getpayorders": "order",
	"api_getpaystats":  "order",

	// === user 用户查询 ===
	"api_getuser":                "user",
	"api_updateuser":             "user",
	"api_getuseruselog":          "user",
	"api_getuserechomeetrecords": "userechomeet",
	"api_dispatchresource":       "user",

	// === transaction 流水 ===
	// 代理在此接口内被强制只看自己派发的流水（handler 内做隔离），其它身份可自由按类型/UID过滤
	"api_getuseruselogspaged":  scopeAny,
	"api_getadminresourcelogs": scopeAny, // 超管查全部，其他账号只能查自己；handler 内做隔离

	// === config 服务配置 ===
	"api_getconfig":    "config",
	"api_addconfig":    "config",
	"api_updateconfig": "config",
	"api_delconfig":    "config",

	// === mcp MCP配置 ===
	"api_getmcpserver":    "mcp",
	"api_getmcpservers":   "mcp",
	"api_addmcpservers":   "mcp",
	"api_updatemcpserver": "mcp",
	"api_delmcpservers":   "mcp",

	// === agent Agent管理 ===
	"api_getagent":    "agent",
	"api_getagents":   "agent",
	"api_addagent":    "agent",
	"api_updateagent": "agent",
	"api_delagent":    "agent",

	// === template 模板管理 ===
	"api_gettemplates":    "template",
	"api_gettemplate":     "template",
	"api_addtemplates":    "template",
	"api_updatetemplates": "template",
	"api_deltemplate":     "template",

	// === channelapp 渠道应用 ===
	"api_getchannelapp":    "channelapp",
	"api_getchannelapps":   "channelapp",
	"api_addchannelapp":    "channelapp",
	"api_uploadchannelapp": "channelapp",
	"api_delchannelapp":    "channelapp",

	// === wakeup 唤醒词管理 ===
	"api_getwakeupvoice":    "wakeup",
	"api_getwakeupvoices":   "wakeup",
	"api_addwakeupvoice":    "wakeup",
	"api_updatewakeupvoice": "wakeup",
	"api_delwakeupvoice":    "wakeup",

	// === sysconfig 系统配置 ===
	"api_getglobalconfig":    "sysconfig",
	"api_addglobalconfigs":   "sysconfig",
	"api_updateglobalconfig": "sysconfig",
	"api_delglobalconfigs":   "sysconfig",

	// === audit 操作日志 ===
	"api_getauditlogs":         "audit",
	"api_getconsolelogs":       "audit",
	"api_getconsolelogfilters": "audit",

	// === agentdashboard 代理仪表盘 ===
	"api_getagentdashboard": scopeAgent,

	// === 工具类接口（无页面归属，登录即可） ===
	"api_sendsmtpemail":  scopeAny,
	"api_translate":      scopeAny,
	"api_getcostoken":    scopeAny,
	"api_getuserrank":    scopeAny, // 用户使用量排行 dashboard / agentdashboard 共用
	"api_getmyadminpool": scopeAny, // 当前账号资源点池查询（派发界面余额展示）
}

// permissionInterceptorComp 权限拦截器组件
type permissionInterceptorComp struct {
	cbase.ModuleCompBase
	service core.IService
	module  *API
}

func (this *permissionInterceptorComp) Init(service core.IService, module core.IModule, comp core.IModuleComp, opt core.IModuleOptions) (err error) {
	this.ModuleCompBase.Init(service, module, comp, opt)
	this.service = service
	this.module = module.(*API)
	return
}

func (this *permissionInterceptorComp) Start() (err error) {
	if err = this.ModuleCompBase.Start(); err != nil {
		return
	}
	var scomp core.IServiceComp
	if scomp, err = this.service.GetComp(comm.SC_ServiceHttpRouteComp); err != nil {
		return
	}
	scomp.(comm.ISC_HttpRouteComp).AddInterceptor(this.checkPermission)
	return
}

// checkPermission 权限校验拦截器
func (this *permissionInterceptorComp) checkPermission(apiName string, session comm.IUserSession, msg interface{}) *pb.ErrorData {
	scope, exists := apiPageMap[apiName]
	if !exists {
		// 未配置的接口默认仅 Admin 可访问，避免新接口意外暴露
		scope = scopeAdmin
	}

	if scope == scopeNone {
		return nil
	}

	identityStr := session.GetMateToString("identity")
	if identityStr == "" {
		return &pb.ErrorData{
			Code:    pb.ErrorCode_NoLogin,
			Message: "未登录，请先登录",
		}
	}
	identity := pb.Identity(session.GetMateToInt32("identity"))
	if identity <= 0 {
		return &pb.ErrorData{
			Code:    pb.ErrorCode_NoLogin,
			Message: "登录信息异常",
		}
	}

	switch scope {
	case scopeAdmin:
		if identity != pb.Identity_Admin {
			return permDenied()
		}
		return nil
	case scopeAny:
		return nil
	case scopeAgent:
		if identity != pb.Identity_Agent {
			return permDenied()
		}
		return nil
	}

	// 按页面授权：Admin/Manager 直通；Agent/Operator 需在 access 中勾选
	if identity == pb.Identity_Admin || identity == pb.Identity_Manager {
		return nil
	}
	if identity != pb.Identity_Agent && identity != pb.Identity_Operator {
		return permDenied()
	}

	account := session.GetMateToString(comm.SessionMeta_UserId)
	if account == "" {
		log.Errorf("[perm] api=%s identity=%d account=empty", apiName, identity)
		return permDenied()
	}
	user, err := this.module.model.findforaccount(account)
	if err != nil || user == nil {
		log.Errorf("[perm] api=%s identity=%d account=%s findforaccount err=%v user=%v", apiName, identity, account, err, user)
		return permDenied()
	}
	if !accessHasPage(user.Access, scope) {
		log.Errorf("[perm] api=%s identity=%d account=%s page=%s access=%q -> denied", apiName, identity, account, scope, user.Access)
		return permDenied()
	}
	log.Debugf("[perm] api=%s identity=%d account=%s page=%s access=%q -> allow", apiName, identity, account, scope, user.Access)
	return nil
}

func accessHasPage(access, page string) bool {
	if access == "" || page == "" {
		return false
	}
	for _, p := range strings.Split(access, ",") {
		if strings.TrimSpace(p) == page {
			return true
		}
	}
	return false
}

func permDenied() *pb.ErrorData {
	return &pb.ErrorData{
		Code:    pb.ErrorCode_InsufficientPermissions,
		Message: "权限不足，需要更高级别权限",
	}
}
