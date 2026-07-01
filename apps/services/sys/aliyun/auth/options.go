package ali_auth

import (
	"yunyan/lego/sys/log"
	"yunyan/lego/utils/mapstructure"
)

type Option func(*Options)
type Options struct {
	Debug           bool //日志是否开启
	Log             log.ILogger
	AccessKeyId     string
	AccessKeySecret string
	Appkey          string
}

func SetAccessKeyId(v string) Option {
	return func(o *Options) {
		o.AccessKeyId = v
	}
}

func SetAccessKeySecret(v string) Option {
	return func(o *Options) {
		o.AccessKeySecret = v
	}
}

func SetAppkey(v string) Option {
	return func(o *Options) {
		o.Appkey = v
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
		options.Log = log.NewTurnlog(options.Debug, log.Clone("sys.ali_auth", 3))
	}
	return options
}

func newOptionsByOption(opts ...Option) Options {
	options := Options{}
	for _, o := range opts {
		o(&options)
	}
	if options.Log == nil {
		options.Log = log.NewTurnlog(options.Debug, log.Clone("sys.ali_auth", 3))
	}
	return options
}
