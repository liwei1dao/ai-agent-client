package main

import (
	"context"
	"yunyan/comm"
	"yunyan/lego"
	"yunyan/modules/agents"
	"yunyan/modules/allhelp"
	"yunyan/modules/analyze"
	"yunyan/modules/echomeet"
	musicmodule "yunyan/modules/music"
	"yunyan/modules/pay"
	"yunyan/modules/user"
	"yunyan/services"
	ali_auth "yunyan/sys/aliyun/auth"
	apple_auth "yunyan/sys/auth/apple"
	facebook_auth "yunyan/sys/auth/facebook"
	firebase_auth "yunyan/sys/auth/firebase"
	google_auth "yunyan/sys/auth/google"
	wechat_auth "yunyan/sys/auth/wechat"
	"yunyan/sys/doubao"
	"yunyan/sys/email"
	"yunyan/sys/google"
	"yunyan/sys/ipinfo"
	"yunyan/sys/musicobj"
	"yunyan/sys/nats"
	"yunyan/sys/pay/alipay"
	"yunyan/sys/pay/appleiap"
	"yunyan/sys/pay/googleiap"
	"yunyan/sys/pay/paypal"
	"yunyan/sys/pay/wechat"
	"yunyan/sys/sms"
	"yunyan/sys/tencentyun/cos"
	"yunyan/sys/websearch/bochasearch"
	"flag"
	"fmt"
	_ "time/tzdata" // 内嵌时区库：保证 analyze 统计时区(默认 Asia/Shanghai)在缺 tzdata 的容器也可解析

	"yunyan/lego/base/rpcx"
	"yunyan/lego/core"
	"yunyan/lego/sys/cron"
	"yunyan/lego/sys/log"
	"yunyan/lego/sys/mysql"
	"yunyan/lego/sys/pools"
	"yunyan/lego/sys/postgres"
	redissys "yunyan/lego/sys/redis"
	"yunyan/lego/sys/wordfilter"
)

/*
服务类型:后台服务
*/
var (
	conf = flag.String("conf", "./conf/home.yaml", "获取需要启动的服务配置文件") //启动服务的Id
)

// @title Home API
// @version 1.0
// @description 智能耳机服务

// @securityDefinitions.apikey BearerAuth
// @in header
// @name Authorization
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
		analyze.NewModule(),
		user.NewModule(),
		agents.NewModule(),
		pay.NewModule(),
		echomeet.NewModule(),
		musicmodule.NewModule(),
		allhelp.NewModule(),
		// bailianmodule.NewModule(),
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
	if err := cron.OnInit(this.GetSettings().Sys["cron"]); err != nil {
		panic(fmt.Sprintf("init sys.cron err: %s", err.Error()))
	} else {
		log.Infof("init sys.cron success!")
	}
	//铭感词过滤
	if err := wordfilter.OnInit(this.GetSettings().Sys["wordfilter"]); err != nil {
		panic(fmt.Sprintf("init sys.wordfilter err: %s", err.Error()))
	} else {
		log.Infof("init sys.wordfilter success!")
	}
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
	// 运维统计管道（埋点转发用）。容错：连不上不阻断业务，待 NATS 就绪重启即可。
	if err := nats.OnInit(this.GetSettings().Sys["nats"]); err != nil {
		log.Errorf("init sys.nats err (埋点转发暂不可用): %s", err.Error())
	} else {
		log.Infof("init sys.nats success!")
	}
	if err := cos.OnInit(this.GetSettings().Sys["cos"]); err != nil {
		panic(fmt.Sprintf("init sys.cos err: %s", err.Error()))
	} else {
		log.Infof("init sys.cos success!")
	}
	//短信服务
	if err := sms.OnInit(this.GetSettings().Sys["sms"]); err != nil {
		panic(fmt.Sprintf("init sys.sms err: %s", err.Error()))
	} else {
		log.Infof("init sys.sms success!")
	}
	///第三方服务验证
	if err := google.OnInit(this.GetSettings().Sys["google"]); err != nil {
		panic(fmt.Sprintf("init sys.google err: %s", err.Error()))
	} else {
		log.Infof("init sys.google success!")
	}
	if err := ali_auth.OnInit(this.GetSettings().Sys["aliyun"]); err != nil {
		panic(fmt.Sprintf("init sys.ali_auth err: %s", err.Error()))
	} else {
		log.Infof("init sys.ali_auth success!")
	}
	// 会议相关单元服务（字节/阿里/Google/微软的转写·翻译·总结）由 echomeet 模块按其
	// modules.echomeet 配置内部初始化，不在此处统一装配。

	///第三方登验证接口
	if err := google_auth.OnInit(this.GetSettings().Sys["google_auth"]); err != nil {
		panic(fmt.Sprintf("init sys.google_auth err: %s", err.Error()))
	} else {
		log.Infof("init sys.google_auth success!")
	}
	if err := apple_auth.OnInit(this.GetSettings().Sys["apple_auth"]); err != nil {
		panic(fmt.Sprintf("init sys.apple_auth err: %s", err.Error()))
	} else {
		log.Infof("init sys.apple_auth success!")
	}
	if err := facebook_auth.OnInit(this.GetSettings().Sys["facebook_auth"]); err != nil {
		panic(fmt.Sprintf("init sys.facebook_auth err: %s", err.Error()))
	} else {
		log.Infof("init sys.facebook_auth success!")
	}
	if err := firebase_auth.OnInit(this.GetSettings().Sys["firebase_auth"]); err != nil {
		panic(fmt.Sprintf("init sys.firebase_auth err: %s", err.Error()))
	} else {
		log.Infof("init sys.firebase_auth success!")
	}
	if err := wechat_auth.OnInit(this.GetSettings().Sys["wechat_auth"]); err != nil {
		panic(fmt.Sprintf("init sys.wechat_auth err: %s", err.Error()))
	} else {
		log.Infof("init sys.wechat_auth success!")
	}

	if err := musicobj.OnInit(this.GetSettings().Sys["musicobj"]); err != nil {
		panic(fmt.Sprintf("init sys.musicobj err: %s", err.Error()))
	} else {
		log.Infof("init sys.musicobj success!")
	}

	if err := email.OnInit(this.GetSettings().Sys["email"]); err != nil {
		panic(fmt.Sprintf("init sys.email err: %s", err.Error()))
	} else {
		log.Infof("init sys.email success!")
	}

	if err := cos.OnInit(this.GetSettings().Sys["cos"]); err != nil {
		panic(fmt.Sprintf("init sys.cos err: %s", err.Error()))
	} else {
		log.Infof("init sys.cos success!")
	}

	if err := wechat.OnInit(this.GetSettings().Sys["wechatpay"]); err != nil {
		panic(fmt.Sprintf("init sys.wechatpay err: %s", err.Error()))
	} else {
		log.Infof("init sys.wechatpay success!")
	}

	if err := alipay.OnInit(this.GetSettings().Sys["alipay"]); err != nil {
		panic(fmt.Sprintf("init sys.alipay err: %s", err.Error()))
	} else {
		log.Infof("init sys.alipay success!")
	}

	if err := paypal.OnInit(this.GetSettings().Sys["paypal"]); err != nil {
		panic(fmt.Sprintf("init sys.paypal err: %s", err.Error()))
	} else {
		log.Infof("init sys.paypal success!")
	}
	if err := appleiap.OnInit(this.GetSettings().Sys["appleiap"]); err != nil {
		panic(fmt.Sprintf("init sys.appleiap err: %s", err.Error()))
	} else {
		log.Infof("init sys.appleiap success!")
	}
	if err := googleiap.OnInit(this.GetSettings().Sys["googleiap"]); err != nil {
		panic(fmt.Sprintf("init sys.googleiap err: %s", err.Error()))
	} else {
		log.Infof("init sys.googleiap success!")
	}
	if err := googleiap.OnInit(this.GetSettings().Sys["googleiap"]); err != nil {
		panic(fmt.Sprintf("init sys.googleiap err: %s", err.Error()))
	} else {
		log.Infof("init sys.googleiap success!")
	}
	if err := doubao.OnInit(this.GetSettings().Sys["doubao"]); err != nil {
		panic(fmt.Sprintf("init sys.doubao err: %s", err.Error()))
	} else {
		log.Infof("init sys.doubao success!")
	}
	if err := ipinfo.OnInit(this.GetSettings().Sys["ipinfo"]); err != nil {
		panic(fmt.Sprintf("init sys.ipinfo err: %s", err.Error()))
	} else {
		log.Infof("init sys.ipinfo success!")
	}
	//aitools
	if err := bochasearch.OnInit(this.GetSettings().Sys["bochasearch"]); err != nil {
		panic(fmt.Sprintf("init sys.bochasearch err: %s", err.Error()))
	} else {
		log.Infof("init sys.bochasearch success!")
	}
	// if err := bailian.OnInit(this.GetSettings().Sys["bailian"]); err != nil {
	// 	panic(fmt.Sprintf("init sys.bailian err: %s", err.Error()))
	// } else {
	// 	log.Infof("init sys.bailian success!")
	// }
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
