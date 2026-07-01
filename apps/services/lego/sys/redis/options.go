package redis

import (
	"yunyan/lego/sys/log"
	"yunyan/lego/utils/mapstructure"
)

type Option func(*Options)
type Options struct {
	Addr      []string // 地址，多地址即集群
	Password  string
	DB        int
	TLS       bool
	KeyPrefix string // key 前缀（如 Console），同实例下各应用互不串扰
	Debug     bool
	Log       log.ILogger
}

func SetAddr(v []string) Option {
	return func(o *Options) { o.Addr = v }
}
func SetPassword(v string) Option {
	return func(o *Options) { o.Password = v }
}
func SetDB(v int) Option {
	return func(o *Options) { o.DB = v }
}
func SetTLS(v bool) Option {
	return func(o *Options) { o.TLS = v }
}
func SetKeyPrefix(v string) Option {
	return func(o *Options) { o.KeyPrefix = v }
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
		options.Log = log.NewTurnlog(options.Debug, log.Clone("sys.redis", 3))
	}
	return options
}

func newOptionsByOption(opts ...Option) Options {
	options := Options{}
	for _, o := range opts {
		o(&options)
	}
	if options.Log == nil {
		options.Log = log.NewTurnlog(options.Debug, log.Clone("sys.redis", 3))
	}
	return options
}
