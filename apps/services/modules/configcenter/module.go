// configcenter 配置中心模块：给客户端提供「公开、免登录」的服务端配置读取接口。
//
// 独立单例服务（services/configcenter），net/http 自起（默认 :8091）。下发内容：
// 服务列表(third_svc_config) + Agent 列表(console_agent) + MCP 数据(console_mcp) + 全局配置(console_global_config)，
// 均为 console 后台配置的数据。因接口公开，整个配置 JSON 用 AES-256-GCM **整包加密**后下发，
// 密钥取自环境变量（默认 CONFIG_SECRET_KEY），客户端用同一密钥解密。
package configcenter

import (
	"yunyan/lego/core"
	"yunyan/modules"
)

func NewModule() core.IModule {
	return new(ConfigCenter)
}

type ConfigCenter struct {
	modules.ModuleBase
	http    *httpComp
	model   *modelComp
	options *Options
}

func (this *ConfigCenter) GetType() core.M_Modules {
	return core.M_Modules("configcenter")
}

func (this *ConfigCenter) NewOptions() (options core.IModuleOptions) {
	return new(Options)
}

func (this *ConfigCenter) Init(service core.IService, module core.IModule, options core.IModuleOptions) (err error) {
	this.options = options.(*Options)
	if err = this.ModuleBase.Init(service, module, options); err != nil {
		return
	}
	return
}

func (this *ConfigCenter) Start() (err error) {
	if err = this.ModuleBase.Start(); err != nil {
		return
	}
	return
}

func (this *ConfigCenter) OnInstallComp() {
	this.ModuleBase.OnInstallComp()
	this.model = this.RegisterComp(new(modelComp)).(*modelComp)
	this.http = this.RegisterComp(new(httpComp)).(*httpComp)
}
