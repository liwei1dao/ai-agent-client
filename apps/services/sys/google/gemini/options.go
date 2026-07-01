package gemini

import (
	"yunyan/lego/sys/log"
	"yunyan/lego/utils/mapstructure"
)

type Option func(*Options)

type Options struct {
	Debug    bool
	Log      log.ILogger
	Apikey   string  // Gemini API Key（AIzaSy... 形式）
	Model    string  // 默认模型 ID，如 gemini-2.5-flash / gemini-2.5-pro
	Endpoint string  // 自定义 endpoint（可选，默认 generativelanguage.googleapis.com）
	Timeout  int     // HTTP 超时（秒），默认 120
}

func SetApikey(v string) Option {
	return func(o *Options) {
		o.Apikey = v
	}
}

func SetModel(v string) Option {
	return func(o *Options) {
		o.Model = v
	}
}

func SetEndpoint(v string) Option {
	return func(o *Options) {
		o.Endpoint = v
	}
}

func SetTimeout(v int) Option {
	return func(o *Options) {
		o.Timeout = v
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
	applyDefaults(&options)
	return options
}

func newOptionsByOption(opts ...Option) Options {
	options := Options{}
	for _, o := range opts {
		o(&options)
	}
	applyDefaults(&options)
	return options
}

func applyDefaults(o *Options) {
	if o.Endpoint == "" {
		o.Endpoint = "https://generativelanguage.googleapis.com"
	}
	if o.Model == "" {
		o.Model = "gemini-2.5-flash"
	}
	if o.Timeout <= 0 {
		o.Timeout = 120
	}
	if o.Log == nil {
		o.Log = log.NewTurnlog(o.Debug, log.Clone("sys.google.gemini", 3))
	}
}
