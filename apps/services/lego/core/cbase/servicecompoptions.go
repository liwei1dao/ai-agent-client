package cbase

import (
	"yunyan/lego/core"
	"yunyan/lego/utils/mapstructure"
)

type ServiceCompOptions struct {
	core.ICompOptions
}

func (this *ServiceCompOptions) LoadConfig(settings map[string]interface{}) (err error) {
	if settings != nil {
		mapstructure.Decode(settings, &this)
	}
	return
}
