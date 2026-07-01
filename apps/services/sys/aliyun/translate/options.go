package translate

import (
	"yunyan/lego/sys/log"
	"yunyan/lego/utils/mapstructure"
)

type Option func(*Options)

type Options struct {
	Debug           bool
	Log             log.ILogger
	AccessKeyId     string // RAM AK
	AccessKeySecret string // RAM AS
	Region          string // 区域，默认 cn-hangzhou
	Scene           string // 翻译场景：general/social/ecommerce/finance/medical/tech，默认 general
	FormatType      string // text | html，默认 text
	Concurrency     int    // 并发翻译条数，默认 5
}

func SetAccessKeyId(v string) Option {
	return func(o *Options) {
		o.AccessKeyId = v
	}
}

func SetAccessKeySecret(v string) Option {
	return func(o *Options) {
		o.AccessKeySecret = v
	}
}

func SetRegion(v string) Option {
	return func(o *Options) {
		o.Region = v
	}
}

func SetScene(v string) Option {
	return func(o *Options) {
		o.Scene = v
	}
}

func SetFormatType(v string) Option {
	return func(o *Options) {
		o.FormatType = v
	}
}

func SetConcurrency(v int) Option {
	return func(o *Options) {
		o.Concurrency = v
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
	if o.Region == "" {
		o.Region = "cn-hangzhou"
	}
	if o.Scene == "" {
		o.Scene = "general"
	}
	if o.FormatType == "" {
		o.FormatType = "text"
	}
	if o.Concurrency <= 0 {
		o.Concurrency = 5
	}
	if o.Log == nil {
		o.Log = log.NewTurnlog(o.Debug, log.Clone("sys.aliyun.translate", 3))
	}
}
