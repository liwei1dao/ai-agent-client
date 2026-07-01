package single

import (
	"fmt"
	"sync"

	"yunyan/lego/base"
	"yunyan/lego/core"
	"yunyan/lego/core/cbase"
	"yunyan/lego/sys/cron"
	"yunyan/lego/sys/event"
	"yunyan/lego/sys/log"
)

/*
单例模式服务容器
独立部署、不接入 etcd/RPCX 集群的服务使用（如 migu 移动灵犀聊天服务）。
仅提供日志、事件、模块装配等基础能力，进程内通过 single.Instance() 获取唯一实例。
*/

var (
	instance base.ISingleService
	once     sync.Once
)

// Instance 获取当前进程内的单例服务容器
func Instance() base.ISingleService {
	return instance
}

type SingleService struct {
	cbase.ServiceBase
	option *Options
}

func (this *SingleService) GetId() string {
	return this.option.Setting.Id
}
func (this *SingleService) GetType() string {
	return this.option.Setting.Type
}
func (this *SingleService) GetVersion() string {
	return this.option.Version
}
func (this *SingleService) GetSettings() core.ServiceSttings {
	return this.option.Setting
}

func (this *SingleService) Configure(option ...Option) {
	this.option = newOptions(option...)
}

func (this *SingleService) Init(service core.IService) (err error) {
	// 注册单例实例（外层 Service 即 core.IService）
	once.Do(func() { instance = service.(base.ISingleService) })
	err = this.ServiceBase.Init(service)
	return
}

func (this *SingleService) InitSys() {
	if err := log.OnInit(this.option.Setting.Sys["log"]); err != nil {
		panic(fmt.Sprintf("sys log Init err:%v", err))
	} else {
		log.Infof("sys log Init success !")
	}
	if err := event.OnInit(this.option.Setting.Sys["event"]); err != nil {
		log.Panicf(fmt.Sprintf("sys event Init err:%v", err))
	} else {
		log.Infof("sys event Init success !")
	}
}

func (this *SingleService) Destroy() (err error) {
	cron.Close()
	err = this.ServiceBase.Destroy()
	return
}
