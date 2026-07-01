package spotify

import (
	"yunyan/lego/utils/mapstructure"
)

type Option func(*Options)
type Options struct {
	ClientID     string
	ClientSecret string
	RedirectURI  string
}

func SetClientID(v string) Option {
	return func(o *Options) {
		o.ClientID = v
	}
}

func SetClientSecret(v string) Option {
	return func(o *Options) {
		o.ClientSecret = v
	}
}

func SetRedirectURI(v string) Option {
	return func(o *Options) {
		o.RedirectURI = v
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
