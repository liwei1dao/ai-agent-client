package wordfilter

import (
	"yunyan/lego/sys/log"
	"yunyan/lego/utils/mapstructure"
)

type Option func(*Options)
type Options struct {
	WorldFile []string //词组文件
	Debug     bool     //日志是否开启
	Log       log.Ilogf
}

func SetWorldFile(v []string) Option {
	return func(o *Options) {
		o.WorldFile = v
	}
}

func SetDebug(v bool) Option {
	return func(o *Options) {
		o.Debug = v
	}
}

func SetLog(v log.Ilogf) Option {
	return func(o *Options) {
		o.Log = v
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
	options.Log = log.NewTurnlog(options.Debug, log.Clone("sys.wordfilter", 3))
	return
}

func newOptionsByOption(opts ...Option) (options *Options, err error) {
	options = &Options{}
	for _, o := range opts {
		o(options)
	}
	options.Log = log.NewTurnlog(options.Debug, log.Clone("sys.wordfilter", 3))
	return
}
