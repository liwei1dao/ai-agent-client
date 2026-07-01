package ipinfo

import (
	"yunyan/lego/sys/log"
	"yunyan/lego/utils/mapstructure"
	"errors"
)

type Option func(*Options)
type Options struct {
	Debug bool //日志是否开启
	Log   log.ILogger

	V4XdbPath   string // ip2region v4 xdb 文件路径，空则禁用 v4 查询
	V6XdbPath   string // ip2region v6 xdb 文件路径，空则禁用 v6 查询
	CachePolicy string // 缓存策略：nocache / vindex / buffer，默认 vindex
	Searchers   int    // 并发查询器数量，默认 10
}

func SetV4XdbPath(v string) Option {
	return func(o *Options) { o.V4XdbPath = v }
}

func SetV6XdbPath(v string) Option {
	return func(o *Options) { o.V6XdbPath = v }
}

func SetCachePolicy(v string) Option {
	return func(o *Options) { o.CachePolicy = v }
}

func SetSearchers(v int) Option {
	return func(o *Options) { o.Searchers = v }
}

func newOptions(config map[string]interface{}, opts ...Option) (options *Options, err error) {
	options = &Options{}
	if config != nil {
		mapstructure.Decode(config, options)
	}
	for _, o := range opts {
		o(options)
	}
	fillDefaults(options)
	if options.Log = log.NewTurnlog(options.Debug, log.Clone("sys.ipinfo", 3)); options.Log == nil {
		err = errors.New("log is nil")
	}
	return
}

func newOptionsByOption(opts ...Option) (options *Options, err error) {
	options = &Options{}
	for _, o := range opts {
		o(options)
	}
	fillDefaults(options)
	if options.Log = log.NewTurnlog(options.Debug, log.Clone("sys.ipinfo", 3)); options.Log == nil {
		err = errors.New("log is nil")
	}
	return
}

func fillDefaults(o *Options) {
	if o.CachePolicy == "" {
		o.CachePolicy = "vindex"
	}
	if o.Searchers <= 0 {
		o.Searchers = 10
	}
}
