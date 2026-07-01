// app 业务服务（独立部署）。
//
// 单例服务：不接 ETCD/RPCX，只驱动 app 模块。自带 HTTP（默认 :8090）对客户端提供
// 登录（邮箱/短信/微信）+ 获取应用配置。依赖 Supabase(postgres) 存用户、redis 存验证码；
// sms/email/wechat 为可选依赖（未配置则对应登录方式在运行时返回错误，不阻断启动）。
//
// 启动：./app -conf ./conf/app.yaml
package main

import (
	"flag"

	"yunyan/lego"
	"yunyan/lego/base/single"
	"yunyan/lego/core"
	"yunyan/lego/sys/log"
	"yunyan/lego/sys/postgres"
	"yunyan/lego/sys/redis"
	"yunyan/modules/app"
	wechat "yunyan/sys/auth/wechat"
	"yunyan/sys/email"
	"yunyan/sys/sms"
)

var conf = flag.String("conf", "./conf/app.yaml", "app 业务服务配置文件")

func main() {
	flag.Parse()
	s := NewService(
		single.SetConfPath(*conf),
		single.SetVersion("1.0.0.0"),
	)
	lego.Run(s, app.NewModule())
}

func NewService(opts ...single.Option) core.IService {
	s := new(Service)
	s.Configure(opts...)
	return s
}

type Service struct {
	single.SingleService
}

// InitSys 在基类之上初始化 postgres（用户库，必备）、redis（验证码，必备），
// 以及可选的 sms/email/wechat（缺配置不阻断启动，对应登录方式运行时报错即可）。
func (this *Service) InitSys() {
	this.SingleService.InitSys()
	if err := postgres.OnInit(this.GetSettings().Sys["postgres"]); err != nil {
		log.Panicf("app: sys.postgres 初始化失败: %v", err)
	} else {
		log.Infof("app: sys.postgres 初始化成功")
	}
	if err := redis.OnInit(this.GetSettings().Sys["redis"]); err != nil {
		log.Panicf("app: sys.redis 初始化失败: %v", err)
	} else {
		log.Infof("app: sys.redis 初始化成功")
	}
	if cfg, ok := this.GetSettings().Sys["sms"]; ok {
		if err := sms.OnInit(cfg); err != nil {
			log.Errorf("app: sys.sms 初始化失败（短信登录暂不可用）: %v", err)
		} else {
			log.Infof("app: sys.sms 初始化成功")
		}
	}
	if cfg, ok := this.GetSettings().Sys["email"]; ok {
		if err := email.OnInit(cfg); err != nil {
			log.Errorf("app: sys.email 初始化失败（邮箱登录暂不可用）: %v", err)
		} else {
			log.Infof("app: sys.email 初始化成功")
		}
	}
	if cfg, ok := this.GetSettings().Sys["wechat"]; ok {
		if err := wechat.OnInit(cfg); err != nil {
			log.Errorf("app: sys.wechat 初始化失败（微信登录暂不可用）: %v", err)
		} else {
			log.Infof("app: sys.wechat 初始化成功")
		}
	}
}
