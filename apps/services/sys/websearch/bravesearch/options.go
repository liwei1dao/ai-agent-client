package bravesearch

import (
	"yunyan/lego/sys/log"
	"yunyan/lego/utils/mapstructure"
)

type Option func(*Options)
type Options struct {
	Debug          bool //日志是否开启
	Log            log.ILogger
	ApiKey         string
	Country        string
	SearchLanguage string
	UILanguage     string
}

func SetApiKey(v string) Option {
	return func(o *Options) {
		o.ApiKey = v
	}
}

func SetCountry(v string) Option {
	return func(o *Options) {
		o.Country = v
	}
}

func SetSearchLanguage(v string) Option {
	return func(o *Options) {
		o.SearchLanguage = v
	}
}

func SetUILanguage(v string) Option {
	return func(o *Options) {
		o.UILanguage = v
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
