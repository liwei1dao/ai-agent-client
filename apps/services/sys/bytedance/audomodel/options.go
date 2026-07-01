package audomodel

import (
	"yunyan/lego/sys/log"
	"yunyan/lego/utils/mapstructure"
)

type Option func(*Options)
type Options struct {
	Debug        bool //日志是否开启
	Log          log.ILogger
	BaseUrl      string
	AppID        string
	Token        string
	ResourceId   string
	ModelName    string
	ModelVersion string
}

func SetBaseUrl(v string) Option {
	return func(o *Options) {
		o.BaseUrl = v
	}
}

func SetAppID(v string) Option {
	return func(o *Options) {
		o.AppID = v
	}
}
func SetToken(v string) Option {
	return func(o *Options) {
		o.Token = v
	}
}

func SetResourceId(v string) Option {
	return func(o *Options) {
		o.ResourceId = v
	}
}
func SetModelName(v string) Option {
	return func(o *Options) {
		o.ModelName = v
	}
}
func SetModelVersion(v string) Option {
	return func(o *Options) {
		o.ModelVersion = v
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
		options.Log = log.NewTurnlog(options.Debug, log.Clone("sys.coze", 3))
	}
	return options
}

func newOptionsByOption(opts ...Option) Options {
	options := Options{}
	for _, o := range opts {
		o(&options)
	}
	if options.Log == nil {
		options.Log = log.NewTurnlog(options.Debug, log.Clone("sys.coze", 3))
	}
	return options
}
