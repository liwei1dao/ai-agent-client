package modules

import (
	"errors"

	"yunyan/lego/core"
	"yunyan/lego/sys/log"

	"github.com/mitchellh/mapstructure"
)

type (
	IOptions interface {
		core.IModuleOptions
		GetDebug() bool
		GetLog() log.ILogger
		GetOutputCSV() bool
	}
	Options struct {
		Debug     bool //日志是否开启
		Log       log.ILogger
		OutputCSV bool //是否输出统计报表
	}
)

func (this *Options) GetDebug() bool {
	return this.Debug
}

func (this *Options) GetLog() log.ILogger {
	return this.Log
}
func (this *Options) GetOutputCSV() bool {
	return this.OutputCSV
}

func (this *Options) LoadConfig(settings map[string]interface{}) (err error) {
	this.Debug = false
	if settings != nil {
		err = mapstructure.Decode(settings, this)
	}

	if this.Log = log.NewTurnlog(this.Debug, log.Clone("", 4)); this.Log == nil {
		err = errors.New("log is nil")
	}
	return
}
