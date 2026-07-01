package google

import "yunyan/lego/utils/mapstructure"

type Option func(*Options)
type Options struct {
	JsonPath string
}

func SetJsonPath(v string) Option {
	return func(o *Options) {
		o.JsonPath = v
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
