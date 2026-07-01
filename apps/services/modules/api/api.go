package api

import (
	"yunyan/modules"

	"yunyan/lego/base"
	"yunyan/lego/core"
)

type apiComp struct {
	modules.MCompHttpGate
	service base.IRPCXService
	module  *API
	options *Options
}

func (this *apiComp) Init(service core.IService, module core.IModule, comp core.IModuleComp, options core.IModuleOptions) (err error) {
	this.MCompHttpGate.Init(service, module, comp, options)
	this.service = service.(base.IRPCXService)
	this.module = module.(*API)
	this.options = options.(*Options)
	return
}

func (this *apiComp) Start() (err error) {
	err = this.MCompHttpGate.Start()
	return
}
