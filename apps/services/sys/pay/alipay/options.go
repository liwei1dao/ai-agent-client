package alipay

import (
	"yunyan/lego/sys/log"
	"yunyan/lego/utils/mapstructure"
)

type Option func(*Options)
type Options struct {
	Debug      bool //日志是否开启
	Log        log.ILogger
	AppID      string "你的支付宝APPID"
	PrivateKey string "你的应用私钥（PKCS8格式）"
	PublicKey  string "支付宝公钥"
}

func SetAppID(v string) Option {
	return func(o *Options) {
		o.AppID = v
	}
}
func SetPrivateKey(v string) Option {
	return func(o *Options) {
		o.PrivateKey = v
	}
}
func SetPublicKey(v string) Option {
	return func(o *Options) {
		o.PublicKey = v
	}
}
func SetDebug(v bool) Option {
	return func(o *Options) {
		o.Debug = v
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
