package googleiap

import (
	"yunyan/lego/sys/log"
	"yunyan/lego/utils/mapstructure"
)

type Options struct {
	Debug bool
	Log   log.ILogger
	// Google 服务账号配置（用于获取 Android Publisher 访问令牌）
	ServiceAccountJSONPath string // 本地 .json 路径
	ServiceAccountJSON     string // 直接传入 JSON 内容（优先级高于 Path）
}

type Option func(*Options)

func SetDebug(v bool) Option {
	return func(o *Options) { o.Debug = v }
}

func SetLog(l log.ILogger) Option {
	return func(o *Options) { o.Log = l }
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
		options.Log = log.NewTurnlog(options.Debug, log.Clone("sys.paypal", 3))
	}
	return options
}

func newOptionsByOption(opts ...Option) Options {
	options := Options{}
	for _, o := range opts {
		o(&options)
	}
	if options.Log == nil {
		options.Log = log.NewTurnlog(options.Debug, log.Clone("sys.paypal", 3))
	}
	return options
}

// Setters
func SetServiceAccountJSONPath(p string) Option {
	return func(o *Options) { o.ServiceAccountJSONPath = p }
}

func SetServiceAccountJSON(j string) Option {
	return func(o *Options) { o.ServiceAccountJSON = j }
}
