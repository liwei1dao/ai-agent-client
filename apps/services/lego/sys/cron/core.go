package cron

import (
	tcron "github.com/robfig/cron/v3"
)

/*
系统描述:定时任务系统,开源cron 的封装
*/
type (
	EntryID tcron.EntryID
	ISys    interface {
		Start()
		Close()
		AddFunc(spec string, cmd func()) (EntryID, error)
		Remove(id EntryID)
	}
)

var (
	defsys ISys
)

func OnInit(config map[string]interface{}, option ...Option) (err error) {
	if defsys, err = newSys(newOptions(config, option...)); err == nil {
		Start()
	}
	return
}

func NewSys(option ...Option) (sys ISys, err error) {
	if sys, err = newSys(newOptionsByOption(option...)); err == nil {
		sys.Start()
	}
	return
}

func Start() {
	defsys.Start()
}

func Close() {
	// gateway/api/mcp 等服务并未初始化 cron，关闭时 RPCXService.Destroy() 会无条件调用本函数。
	// 加 nil 保护，避免未初始化时空指针 panic 把真正的关闭/错误日志冲乱。
	if defsys != nil {
		defsys.Close()
	}
}

func AddFunc(spec string, cmd func()) (EntryID, error) {
	return defsys.AddFunc(spec, cmd)
}

func Remove(id EntryID) {
	defsys.Remove(id)
}
