package main

import (
	"yunyan/lego"
	"yunyan/modules/migu"
	migusys "yunyan/sys/migu"
	"flag"
	"fmt"

	"yunyan/lego/base/single"
	"yunyan/lego/core"
	"yunyan/lego/sys/log"
)

/*
服务类型: 移动灵犀聊天服务（migu）
独立部署，对外暴露 OpenAI 兼容接口，内部调咪咕灵犀。不接入 etcd/RPCX 集群，使用单例服务容器。
*/
var (
	conf = flag.String("conf", "./conf/migu.yaml", "获取需要启动的服务配置文件")
)

func main() {
	flag.Parse()
	s := NewService(
		single.SetConfPath(*conf),
		single.SetVersion("1.0.0.0"),
	)
	s.OnInstallComp() // 单例容器，不装备任何集群组件
	lego.Run(s,
		migu.NewModule(),
	)
}

func NewService(ops ...single.Option) core.IService {
	s := new(Service)
	s.Configure(ops...)
	return s
}

type Service struct {
	single.SingleService
}

func (this *Service) InitSys() {
	this.SingleService.InitSys()
	if err := migusys.OnInit(this.GetSettings().Sys["migu"]); err != nil {
		panic(fmt.Sprintf("init sys.migu err: %s", err.Error()))
	} else {
		log.Infof("init sys.migu success!")
	}
}
