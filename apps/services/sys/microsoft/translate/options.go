package translate

import (
	"yunyan/lego/sys/log"
	"yunyan/lego/utils/mapstructure"
)

type Option func(*Options)
type Options struct {
	Debug    bool //日志是否开启
	Log      log.ILogger
	Key      string // Azure Translator 订阅 Key
	Region   string // 资源区域，如 eastasia / southeastasia
	Endpoint string // 默认 https://api.cognitive.microsofttranslator.com
}

func SetKey(v string) Option {
	return func(o *Options) {
		o.Key = v
	}
}
func SetRegion(v string) Option {
	return func(o *Options) {
		o.Region = v
	}
}
func SetEndpoint(v string) Option {
	return func(o *Options) {
		o.Endpoint = v
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
	if options.Endpoint == "" {
		options.Endpoint = "https://api.cognitive.microsofttranslator.com"
	}
	if options.Log == nil {
		options.Log = log.NewTurnlog(options.Debug, log.Clone("sys.microsoft.translate", 3))
	}
	return options
}

func newOptionsByOption(opts ...Option) Options {
	options := Options{}
	for _, o := range opts {
		o(&options)
	}
	if options.Endpoint == "" {
		options.Endpoint = "https://api.cognitive.microsofttranslator.com"
	}
	if options.Log == nil {
		options.Log = log.NewTurnlog(options.Debug, log.Clone("sys.microsoft.translate", 3))
	}
	return options
}
