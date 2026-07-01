package cos

import (
	"yunyan/lego/sys/log"
	"yunyan/lego/utils/mapstructure"
)

type Option func(*Options)
type Options struct {
	Debug      bool //日志是否开启
	Log        log.ILogger
	SecretID   string
	SecretKey  string
	Region     string
	AppId      string
	BucketName string
	BucketURL  string
	DomainName string // 自定义域名
}

func SetSecretID(v string) Option {
	return func(o *Options) {
		o.SecretID = v
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
func SetAppId(v string) Option {
	return func(o *Options) {
		o.AppId = v
	}
}
func SetBucketName(v string) Option {
	return func(o *Options) {
		o.BucketName = v
	}
}
func SetBucketURL(v string) Option {
	return func(o *Options) {
		o.BucketURL = v
	}
}
func SetDomainName(v string) Option {
	return func(o *Options) {
		o.DomainName = v
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
