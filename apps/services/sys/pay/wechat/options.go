package wechat

import (
	"yunyan/lego/sys/log"
	"yunyan/lego/utils/mapstructure"
)

type Option func(*Options)
type Options struct {
	Debug          bool //日志是否开启
	Log            log.ILogger
	AppID          string // 公众号/小程序APPID
	MchID          string // 商户号
	ApiV3Key       string // APIv3密钥
	PrivateKeyPath string // 商户私钥路径（.pem）
	CertSerialNo   string // 商户证书序列号
}

func SetAppID(v string) Option {
	return func(o *Options) {
		o.AppID = v
	}
}
func SetMchID(v string) Option {
	return func(o *Options) {
		o.MchID = v
	}
}
func SetApiV3Key(v string) Option {
	return func(o *Options) {
		o.ApiV3Key = v
	}
}
func SetPrivateKeyPath(v string) Option {
	return func(o *Options) {
		o.PrivateKeyPath = v
	}
}
func SetCertSerialNo(v string) Option {
	return func(o *Options) {
		o.CertSerialNo = v
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
