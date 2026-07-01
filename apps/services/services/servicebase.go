package services

import (
	"yunyan/lego/base/rpcx"
	"yunyan/lego/core"
	"yunyan/lego/sys/lgid"
	"yunyan/lego/sys/log"
	"fmt"
)

// 基础服务对象
type ServiceBase struct {
	rpcx.RPCXService
}

func (this *ServiceBase) Init(service core.IService) (err error) {
	if err = this.RPCXService.Init(service); err != nil {
		return
	}
	return
}

// 初始化相关系统
func (this *ServiceBase) InitSys() {
	this.RPCXService.InitSys()
	//存储系统
	if err := lgid.OnInit(this.GetSettings().Sys["lgid"]); err != nil {
		panic(fmt.Sprintf("init sys.db err: %s", err.Error()))
	} else {
		log.Infof("init sys.db success!")
	}

}
