package api

import (
	"yunyan/comm"
	"yunyan/lego/core"
	"yunyan/lego/core/cbase"
	"yunyan/lego/sys/log"
	"yunyan/lego/sys/mysql"
	"yunyan/pb"
	"time"
)

// modelAuditComp 操作日志数据组件
type modelAuditComp struct {
	cbase.ModuleCompBase
	module  *API
	service core.IService
}

func (this *modelAuditComp) Init(service core.IService, module core.IModule, comp core.IModuleComp, opt core.IModuleOptions) (err error) {
	this.ModuleCompBase.Init(service, module, comp, opt)
	this.module = module.(*API)
	this.service = service
	if err = mysql.CreateTable(comm.TableConsoleLog, &pb.DBConsoleLog{}); err != nil {
		this.module.Errorln(err)
	}
	return
}

func (this *modelAuditComp) Start() (err error) {
	if err = this.ModuleCompBase.Start(); err != nil {
		return
	}
	// 向服务路由组件注册审计钩子
	var scomp core.IServiceComp
	if scomp, err = this.service.GetComp(comm.SC_ServiceHttpRouteComp); err != nil {
		return
	}
	scomp.(comm.ISC_HttpRouteComp).AddApiAuditHook(this.onApiAudit)
	return
}

// onApiAudit 审计回调：判断是否需要记录，异步写入数据库
func (this *modelAuditComp) onApiAudit(apiName string, session comm.IUserSession, reqBody []byte, respBody []byte, code int32, costMs int64) {
	if !auditableAPIMap[apiName] {
		return
	}
	reqStr := string(reqBody)
	respStr := ""
	if code != 0 {
		respStr = string(respBody)
	}
	consoleLog := &pb.DBConsoleLog{
		Account:   session.GetUserId(),
		ApiName:   apiName,
		Request:   reqStr,
		Response:  respStr,
		Code:      code,
		Ip:        session.GetMateToString(comm.SessionMeta_IP),
		CostMs:    costMs,
		CreatedAt: time.Now().Unix(),
	}
	if err := mysql.Insert(comm.TableConsoleLog, consoleLog); err != nil {
		log.Errorf("[ConsoleLog] insert err: %v", err)
	}
}

// getConsoleLogs 查询操作日志
func (this *modelAuditComp) getConsoleLogs(where string, args ...interface{}) (logs []*pb.DBConsoleLog, err error) {
	logs = make([]*pb.DBConsoleLog, 0)
	err = mysql.Find(comm.TableConsoleLog, &logs, where, args...)
	return
}

// getDistinctAccounts 获取去重的操作人列表
func (this *modelAuditComp) getDistinctAccounts() (accounts []string, err error) {
	accounts = make([]string, 0)
	tx := mysql.Raw("SELECT DISTINCT account FROM " + comm.TableConsoleLog + " ORDER BY account")
	err = tx.Scan(&accounts).Error
	return
}

// getDistinctApiNames 获取去重的接口名称列表
func (this *modelAuditComp) getDistinctApiNames() (apiNames []string, err error) {
	apiNames = make([]string, 0)
	tx := mysql.Raw("SELECT DISTINCT api_name FROM " + comm.TableConsoleLog + " ORDER BY api_name")
	err = tx.Scan(&apiNames).Error
	return
}
