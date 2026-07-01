package api

import (
	"yunyan/comm"
	"yunyan/lego/core"
	"yunyan/modules"
)

func NewModule() core.IModule {
	m := new(API)
	return m
}

type API struct {
	modules.ModuleBase
	api           *apiComp
	model         *modelComp
	modelAudit    *modelAuditComp
	statConsumer  *statConsumerComp
	permIntercept *permissionInterceptorComp
	options       *Options
}

func (this *API) GetType() core.M_Modules {
	return comm.ModuleApi
}

func (this *API) NewOptions() (options core.IModuleOptions) {
	return new(Options)
}

func (this *API) Init(service core.IService, module core.IModule, options core.IModuleOptions) (err error) {
	this.options = options.(*Options)
	if err = this.ModuleBase.Init(service, module, options); err != nil {
		return
	}
	return
}

func (this *API) Start() (err error) {
	if err = this.ModuleBase.Start(); err != nil {
		return
	}
	return
}

func (this *API) OnInstallComp() {
	this.ModuleBase.OnInstallComp()
	this.api = this.RegisterComp(new(apiComp)).(*apiComp)
	this.model = this.RegisterComp(new(modelComp)).(*modelComp)
	this.modelAudit = this.RegisterComp(new(modelAuditComp)).(*modelAuditComp)
	this.statConsumer = this.RegisterComp(new(statConsumerComp)).(*statConsumerComp)
	this.permIntercept = this.RegisterComp(new(permissionInterceptorComp)).(*permissionInterceptorComp)
}
