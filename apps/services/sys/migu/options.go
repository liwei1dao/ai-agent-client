package migu

import (
	"yunyan/lego/sys/log"
	"yunyan/lego/utils/mapstructure"
)

type Option func(*Options)

type Options struct {
	Debug           bool              // 日志是否开启
	Log             log.ILogger       //
	BaseURL         string            // 咪咕灵犀请求地址，默认走灰度
	DefaultDeviceId string            // 缺省设备ID（请求未携带时使用）
	TimeoutSecond   int               // 整个流式请求的超时时间（秒），默认 300
	Headers         map[string]string // 额外请求头（如鉴权 token，按咪咕侧要求填充）
}

func SetBaseURL(v string) Option {
	return func(o *Options) {
		o.BaseURL = v
	}
}

func SetDefaultDeviceId(v string) Option {
	return func(o *Options) {
		o.DefaultDeviceId = v
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
	fillDefault(&options)
	return options
}

func newOptionsByOption(opts ...Option) Options {
	options := Options{}
	for _, o := range opts {
		o(&options)
	}
	fillDefault(&options)
	return options
}

func fillDefault(options *Options) {
	if options.BaseURL == "" {
		options.BaseURL = BaseURLGray
	}
	if options.TimeoutSecond <= 0 {
		options.TimeoutSecond = 300
	}
	if options.Log == nil {
		options.Log = log.NewTurnlog(options.Debug, log.Clone("sys.migu", 3))
	}
}
