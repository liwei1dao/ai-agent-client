package music

import (
	"yunyan/lego/utils/mapstructure"
)

type Option func(*Options)
type Options struct {
	ApiBaseUrl string
	Cookie     string
}

func SetApiBaseUrl(v string) Option {
	return func(o *Options) {
		o.ApiBaseUrl = v
	}
}
func SetCookie(v string) Option {
	return func(o *Options) {
		o.Cookie = v
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
	return options
}

func newOptionsByOption(opts ...Option) Options {
	options := Options{}
	for _, o := range opts {
		o(&options)
	}
	return options
}
