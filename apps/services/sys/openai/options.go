package openai

import (
	"yunyan/lego/sys/log"

	"github.com/mitchellh/mapstructure"
)

type (
	Option  func(*Options)
	Options struct {
		Debug       bool //日志是否开启
		Log         log.ILogger
		BaseURL     string
		Token       string
		Model       string
		Maxfunccall int //最大执行次数
	}
)

func SetDebug(v bool) Option {
	return func(o *Options) {
		o.Debug = v
	}
}

func SetLog(v log.ILogger) Option {
	return func(o *Options) {
		o.Log = v
	}
}
func SetBaseURL(v string) Option {
	return func(o *Options) {
		o.BaseURL = v
	}
}
func SetToken(v string) Option {
	return func(o *Options) {
		o.Token = v
	}
}

func SetModel(v string) Option {
	return func(o *Options) {
		o.Model = v
	}
}

func SetMaxfunccall(v int) Option {
	return func(o *Options) {
		o.Maxfunccall = v
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
		options.Log = log.NewTurnlog(options.Debug, log.Clone("sys.openai", 3))
	}
	return options
}

func newOptionsByOption(opts ...Option) Options {
	options := Options{}
	for _, o := range opts {
		o(&options)
	}
	if options.Log == nil {
		options.Log = log.NewTurnlog(options.Debug, log.Clone("sys.openai", 3))
	}
	return options
}
