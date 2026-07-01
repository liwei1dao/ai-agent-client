package doubao

import (
	"yunyan/lego/sys/log"
	"yunyan/lego/utils/mapstructure"
)

type Option func(*Options)
type Options struct {
	Debug  bool //日志是否开启
	Log    log.ILogger
	Apikey string
	Model  string
}

func SetApikey(v string) Option {
	return func(o *Options) {
		o.Apikey = v
	}
}
func SetModel(v string) Option {
	return func(o *Options) {
		o.Model = v
	}
}

func newOptions(config map[string]interface{}, opts ...Option) Options {
	options := Options{}
	if config != nil {
		mapstructure.Decode(config, &options)
	}
	for _, o := range opts {
		o(&options)
	}
	if options.Log == nil {
		options.Log = log.NewTurnlog(options.Debug, log.Clone("sys.doubao", 3))
	}
	return options
}

func newOptionsByOption(opts ...Option) Options {
	options := Options{}
	for _, o := range opts {
		o(&options)
	}
	if options.Log == nil {
		options.Log = log.NewTurnlog(options.Debug, log.Clone("sys.doubao", 3))
	}
	return options
}
