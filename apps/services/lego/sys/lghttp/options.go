package lghttp

import (
	"yunyan/lego/sys/log"
	"yunyan/lego/utils/mapstructure"
)

type Option func(*Options)
type Options struct {
	Debug           bool //日志是否开启
	Log             log.ILogger
	MaxConnsPerHost int // 控制每个主机的最大连接数
	ReqTimeOut      int // 请求超时时间 单位秒
}

func newOptions(config map[string]interface{}, opts ...Option) Options {
	options := Options{
		MaxConnsPerHost: 100,
		ReqTimeOut:      3,
	}
	if config != nil {
		mapstructure.Decode(config, &options)
	}
	for _, o := range opts {
		o(&options)
	}
	if options.Log == nil {
		options.Log = log.NewTurnlog(options.Debug, log.Clone("sys.fasthttp", 3))
	}
	return options
}

func newOptionsByOption(opts ...Option) Options {
	options := Options{
		MaxConnsPerHost: 100,
		ReqTimeOut:      3,
	}
	for _, o := range opts {
		o(&options)
	}
	if options.Log == nil {
		options.Log = log.NewTurnlog(options.Debug, log.Clone("sys.fasthttp", 3))
	}
	return options
}
