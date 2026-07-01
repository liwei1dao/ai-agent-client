// 后台控制面服务（独立部署）。
//
// 单例服务：不接 ETCD、不参与集群服务发现，只驱动 console 模块。主库用 Supabase(postgres) +
// 独立 redis（见 modules/console/store.go），存 app_registry 注册表 + stats_global_day。
// 注册表把各应用的「地址 + 设备库/业务库 DSN + NATS 事件通道」登记进来；按"选中应用"用
// buildAppConn 动态建 MySQL 连接并缓存，所有后台操作直连目标应用库；配置变更经 NATS 下发。
//
// 启动：./console -conf ./conf/console.yaml
package main

import (
	"flag"
	_ "time/tzdata" // 内嵌时区库：保证统计时区(默认 Asia/Shanghai)在缺 tzdata 的容器也可解析

	"yunyan/lego"
	"yunyan/lego/base/single"
	"yunyan/lego/core"
	"yunyan/lego/sys/log"
	"yunyan/lego/sys/postgres"
	"yunyan/modules/console"
	"yunyan/sys/email"
	"yunyan/sys/nats"
	"yunyan/sys/tencentyun/cos"

	"yunyan/lego/sys/redis"
)

var conf = flag.String("conf", "./conf/console.yaml", "后台控制面服务配置文件")

func main() {
	flag.Parse()
	s := NewService(
		single.SetConfPath(*conf),
		single.SetVersion("1.0.0.0"),
	)
	lego.Run(s, console.NewModule())
}

func NewService(opts ...single.Option) core.IService {
	s := new(Service)
	s.Configure(opts...)
	return s
}

// Service 控制面服务对象：单例服务（lego/base/single），不接 ETCD。
type Service struct {
	single.SingleService
}

// InitSys 在基类（log + event）之上，按子系统各自 OnInit 初始化 console 主库(postgres)、redis、NATS。
// 主库存注册表与统计，各应用连接由 registryComp 按需 buildAppConn（见 modules/console/registry.go）。
// postgres/redis 为必备依赖，初始化失败即 panic；NATS 不可达不阻断启动（发事件容错，待就绪后即可下发）。
func (this *Service) InitSys() {
	this.SingleService.InitSys()
	if err := postgres.OnInit(this.GetSettings().Sys["postgres"]); err != nil {
		log.Panicf("console: sys.postgres（主库）初始化失败: %v", err)
	} else {
		log.Infof("console: sys.postgres（主库）初始化成功")
	}
	if err := redis.OnInit(this.GetSettings().Sys["redis"]); err != nil {
		log.Panicf("console: sys.redis 初始化失败: %v", err)
	} else {
		log.Infof("console: sys.redis 初始化成功")
	}
	if err := nats.OnInit(this.GetSettings().Sys["nats"]); err != nil {
		log.Errorf("console: sys.nats 初始化失败（配置事件下发暂不可用，需 NATS 就绪后重启）: %v", err)
	} else {
		log.Infof("console: sys.nats 初始化成功")
	}
	// COS 仅 getcostoken（产品图片直传）用；未配置不阻断启动，该接口届时返回错误即可。
	if err := cos.OnInit(this.GetSettings().Sys["cos"]); err != nil {
		log.Errorf("console: sys.cos 初始化失败（getcostoken 暂不可用）: %v", err)
	} else {
		log.Infof("console: sys.cos 初始化成功")
	}
	// email 仅 sendsmtpemail（生产设备码清单下发）用；email.OnInit 配置不全会直接 panic，
	// 故仅当 yaml 配了 email 块时才初始化，未配置则跳过（该接口届时返回错误即可）。
	if cfg, ok := this.GetSettings().Sys["email"]; ok {
		if err := email.OnInit(cfg); err != nil {
			log.Errorf("console: sys.email 初始化失败（sendsmtpemail 暂不可用）: %v", err)
		} else {
			log.Infof("console: sys.email 初始化成功")
		}
	}
}
