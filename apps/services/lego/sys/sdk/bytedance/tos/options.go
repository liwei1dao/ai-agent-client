package tos

import (
	"yunyan/lego/sys/log"
	"yunyan/lego/utils/mapstructure"
)

type Option func(*Options)
type Options struct {
	Debug      bool //日志是否开启
	Log        log.ILogger
	AsccessKey string
	SecretKey  string
	Endpoint   string
	Region     string
	BucketName string
}

func SetAsccessKey(v string) Option {
	return func(o *Options) {
		o.AsccessKey = v
	}
}
func SetSecretKey(v string) Option {
	return func(o *Options) {
		o.SecretKey = v
	}
}
func SetRegion(v string) Option {
	return func(o *Options) {
		o.Region = v
	}
}

func SetBucketName(v string) Option {
	return func(o *Options) {
		o.BucketName = v
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
		options.Log = log.NewTurnlog(options.Debug, log.Clone("sys.tavily", 3))
	}
	return options
}

func newOptionsByOption(opts ...Option) Options {
	options := Options{}
	for _, o := range opts {
		o(&options)
	}
	if options.Log == nil {
		options.Log = log.NewTurnlog(options.Debug, log.Clone("sys.tavily", 3))
	}
	return options
}
