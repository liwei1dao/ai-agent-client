package main

import (
	"yunyan/lego"
	"yunyan/modules/mcp"
	"yunyan/services"
	"flag"
	"fmt"

	"yunyan/lego/base/rpcx"
	"yunyan/lego/core"
	"yunyan/lego/sys/log"
	"yunyan/lego/sys/mysql"
)

/*
服务类型:ai服务
*/
var (
	conf = flag.String("conf", "./conf/mcp.yaml", "获取需要启动的服务配置文件") //启动服务的Id
)

func main() {
	flag.Parse()
	s := NewService(
		rpcx.SetConfPath(*conf),
		rpcx.SetVersion("1.0.0.0"),
	)
	s.OnInstallComp( //装备组件
	)
	lego.Run(s, //运行模块
		mcp.NewModule(),
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
	//业务库(MySQL)：mcp 任务工具(add/cancel/get user task)读写 allhelp_task / user 表
	if err := mysql.OnInit(this.GetSettings().Sys["mysql"]); err != nil {
		panic(fmt.Sprintf("init sys.mysql err: %s", err.Error()))
	} else {
		log.Infof("init sys.mysql success!")
	}
}
