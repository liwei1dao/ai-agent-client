package juhe

import (
	"yunyan/lego/sys/log"
	"yunyan/lego/utils/mapstructure"
	"errors"
)

type Option func(*Options)
type Options struct {
	Debug                bool //日志是否开启
	Log                  log.ILogger
	SimpleWeather_ApiKey string //查询天气的ApiKey
	Finance_ApiKey       string //查询股票的ApiKey
	Toutiao_ApiKey       string //查询头条的ApiKey
}

func SetSimpleWeather_ApiKey(v string) Option {
	return func(o *Options) {
		o.SimpleWeather_ApiKey = v
	}
}

func SetFinance_ApiKey(v string) Option {
	return func(o *Options) {
		o.Finance_ApiKey = v
	}
}

func SetToutiao_ApiKey(v string) Option {
	return func(o *Options) {
		o.Toutiao_ApiKey = v
	}
}

func newOptions(config map[string]interface{}, opts ...Option) (options *Options, err error) {
	options = &Options{}
	if config != nil {
		mapstructure.Decode(config, options)
	}
	for _, o := range opts {
		o(options)
	}
	if options.Log = log.NewTurnlog(options.Debug, log.Clone("sys.juhe", 3)); options.Log == nil {
		err = errors.New("log is nil")
	}
	return
}

func newOptionsByOption(opts ...Option) (options *Options, err error) {
	options = &Options{}
	for _, o := range opts {
		o(options)
	}
	if options.Log = log.NewTurnlog(options.Debug, log.Clone("sys.juhe", 3)); options.Log == nil {
		err = errors.New("log is nil")
	}
	return
}
