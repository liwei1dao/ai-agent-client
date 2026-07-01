// console 模块：全能助手 App 的后台控制面。
//
// 独立单例服务（services/console），自带 net/http 服务（:8080）对外提供管理后台接口，
// 并托管 SPA 静态目录（StaticDir，见 apps/admin 构建产物）。数据落 Supabase Postgres。
// 仅四个配置域：服务配置(third_svc_config) / Agent / MCP / 全局配置；登录校验 yaml 引导超管。
//
// 不接 RPCX 集群，因此不使用 modules.MCompHttpGate（那个把 service 强转 IRPCXService），
// 而是 httpComp 自己起标准库 HTTP 服务、按 /console/api/<method> 分发。
package console

import (
	"yunyan/comm"
	"yunyan/lego/core"
	"yunyan/modules"
)

func NewModule() core.IModule {
	return new(Console)
}

type Console struct {
	modules.ModuleBase
	http    *httpComp
	model   *modelComp
	options *Options
}

func (this *Console) GetType() core.M_Modules {
	return comm.ModuleConsole
}

func (this *Console) NewOptions() (options core.IModuleOptions) {
	return new(Options)
}

func (this *Console) Init(service core.IService, module core.IModule, options core.IModuleOptions) (err error) {
	this.options = options.(*Options)
	if err = this.ModuleBase.Init(service, module, options); err != nil {
		return
	}
	return
}

func (this *Console) Start() (err error) {
	if err = this.ModuleBase.Start(); err != nil {
		return
	}
	return
}

func (this *Console) OnInstallComp() {
	this.ModuleBase.OnInstallComp()
	this.model = this.RegisterComp(new(modelComp)).(*modelComp)
	this.http = this.RegisterComp(new(httpComp)).(*httpComp)
}
