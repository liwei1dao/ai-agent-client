// app 模块：全能助手客户端的对外业务后端。
//
// 独立单例服务（services/app），net/http 自起（默认 :8090），不接 RPCX。提供：
//   - 登录：邮箱验证码 / 短信验证码 / 微信 OAuth（复用 sys/email、sys/sms、sys/auth/wechat）
//   - 获取应用配置：把 console 配置的全局项 + 启用的 Agent 下发给客户端
// 会话凭证用 HS256 JWT（与 console 一致）。验证码存 Redis。
package app

import (
	"yunyan/lego/core"
	"yunyan/modules"
)

func NewModule() core.IModule {
	return new(App)
}

type App struct {
	modules.ModuleBase
	http    *httpComp
	model   *modelComp
	options *Options
}

func (this *App) GetType() core.M_Modules {
	return core.M_Modules("app")
}

func (this *App) NewOptions() (options core.IModuleOptions) {
	return new(Options)
}

func (this *App) Init(service core.IService, module core.IModule, options core.IModuleOptions) (err error) {
	this.options = options.(*Options)
	if err = this.ModuleBase.Init(service, module, options); err != nil {
		return
	}
	return
}

func (this *App) Start() (err error) {
	if err = this.ModuleBase.Start(); err != nil {
		return
	}
	return
}

func (this *App) OnInstallComp() {
	this.ModuleBase.OnInstallComp()
	this.model = this.RegisterComp(new(modelComp)).(*modelComp)
	this.http = this.RegisterComp(new(httpComp)).(*httpComp)
}
