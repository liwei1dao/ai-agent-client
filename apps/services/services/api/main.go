package main

import (
	"context"
	"yunyan/comm"
	"yunyan/lego"
	"yunyan/modules/api"
	"yunyan/services"
	"yunyan/sys/email"
	"yunyan/sys/microsoft/translate"
	"yunyan/sys/tencentyun/cos"
	"flag"
	"fmt"

	"yunyan/lego/base/rpcx"
	"yunyan/lego/core"
	"yunyan/lego/sys/log"
	"yunyan/lego/sys/mysql"
	"yunyan/lego/sys/pools"
	"yunyan/lego/sys/postgres"
	redissys "yunyan/lego/sys/redis"
)

/*
服务类型:ai服务
*/
var (
	conf = flag.String("conf", "./conf/api.yaml", "获取需要启动的服务配置文件") //启动服务的Id
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
		api.NewModule(),
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
	pools.Add(comm.Pool_UserSession, func() comm.IUserSession { return comm.NewUserSession() })
	//业务库(MySQL)
	if err := mysql.OnInit(this.GetSettings().Sys["mysql"]); err != nil {
		panic(fmt.Sprintf("init sys.mysql err: %s", err.Error()))
	} else {
		log.Infof("init sys.mysql success!")
	}
	//公共库(PostgreSQL/Supabase，含只读副本)
	if err := postgres.OnInit(this.GetSettings().Sys["postgres"]); err != nil {
		panic(fmt.Sprintf("init sys.postgres err: %s", err.Error()))
	} else {
		log.Infof("init sys.postgres success!")
	}
	//Redis
	if err := redissys.OnInit(this.GetSettings().Sys["redis"]); err != nil {
		panic(fmt.Sprintf("init sys.redis err: %s", err.Error()))
	} else {
		log.Infof("init sys.redis success!")
	}
	if err := cos.OnInit(this.GetSettings().Sys["cos"]); err != nil {
		panic(fmt.Sprintf("init sys.cos err: %s", err.Error()))
	} else {
		log.Infof("init sys.cos success!")
	}

	if err := email.OnInit(this.GetSettings().Sys["email"]); err != nil {
		panic(fmt.Sprintf("init sys.email err: %s", err.Error()))
	} else {
		log.Infof("init sys.email success!")
	}

	if err := translate.OnInit(this.GetSettings().Sys["translate"]); err != nil {
		log.Warnf("init sys.translate err: %s (翻译服务未配置，翻译功能不可用)", err.Error())
	} else {
		log.Infof("init sys.translate success!")
	}

}

func (this *Service) GetUserSession(ctx context.Context, meta map[string]string) (session comm.IUserSession) {
	session = pools.Get[comm.IUserSession](comm.Pool_UserSession)
	session.SetSession(ctx, meta)
	return
}

func (this *Service) PutUserSession(session comm.IUserSession) {
	session.Reset()
	pools.Put(comm.Pool_UserSession, session)
}
