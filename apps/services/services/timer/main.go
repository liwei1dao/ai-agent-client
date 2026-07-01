package main

import (
	"yunyan/lego"
	"yunyan/modules/timer"
	"yunyan/services"
	"flag"
	"fmt"

	"yunyan/lego/base/rpcx"
	"yunyan/lego/core"
	"yunyan/lego/sys/cron"
	"yunyan/lego/sys/log"
	redissys "yunyan/lego/sys/redis"
)

/*
服务类型:定时任务服务
*/
var (
	conf = flag.String("conf", "./conf/timer.yaml", "获取需要启动的服务配置文件") //启动服务的Id
)

func main() {
	flag.Parse()
	s := NewService(
		rpcx.SetConfPath(*conf),
		rpcx.SetVersion("1.0.0.0"),
	)
	s.OnInstallComp( //装备组件
		services.NewHttpRouteComp(),
	)
	lego.Run(s, //运行模块
		timer.NewModule(),
	)
}

func NewService(ops ...rpcx.Option) core.IService {
	s := new(Service)
	s.Configure(ops...)
	return s
}

// worker 的服务对象定义
type Service struct {
	services.ServiceBase
}

// 初始化worker需要的一些系统工具
func (this *Service) InitSys() {
	this.ServiceBase.InitSys()

	//定时驱动
	if err := cron.OnInit(this.GetSettings().Sys["cron"]); err != nil {
		panic(fmt.Sprintf("init sys.cron err: %s", err.Error()))
	} else {
		log.Infof("init sys.cron success!")
	}
	//Redis（timer 仅用到 Redis）
	if err := redissys.OnInit(this.GetSettings().Sys["redis"]); err != nil {
		panic(fmt.Sprintf("init sys.redis err: %s", err.Error()))
	} else {
		log.Infof("init sys.redis success!")
	}

}
