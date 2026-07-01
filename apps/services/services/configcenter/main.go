// 配置中心服务（独立部署）。
//
// 单例服务：不接 ETCD/RPCX，只驱动 configcenter 模块。自带 HTTP（默认 :8091），
// 对客户端提供「公开、免登录」的应用配置读取（整包 AES-256-GCM 加密）。只读 Supabase(postgres)
// 里 console 写入的配置表。加密密钥取自环境变量 CONFIG_SECRET_KEY。
//
// 启动：CONFIG_SECRET_KEY=xxx ./configcenter -conf ./conf/configcenter.yaml
package main

import (
	"flag"

	"yunyan/lego"
	"yunyan/lego/base/single"
	"yunyan/lego/core"
	"yunyan/lego/sys/log"
	"yunyan/lego/sys/postgres"
	"yunyan/modules/configcenter"
)

var conf = flag.String("conf", "./conf/configcenter.yaml", "配置中心服务配置文件")

func main() {
	flag.Parse()
	s := NewService(
		single.SetConfPath(*conf),
		single.SetVersion("1.0.0.0"),
	)
	lego.Run(s, configcenter.NewModule())
}

func NewService(opts ...single.Option) core.IService {
	s := new(Service)
	s.Configure(opts...)
	return s
}

type Service struct {
	single.SingleService
}

// InitSys 仅需 postgres（只读 console 配置表）。
func (this *Service) InitSys() {
	this.SingleService.InitSys()
	if err := postgres.OnInit(this.GetSettings().Sys["postgres"]); err != nil {
		log.Panicf("configcenter: sys.postgres 初始化失败: %v", err)
	} else {
		log.Infof("configcenter: sys.postgres 初始化成功")
	}
}
