package sms

import (
	"yunyan/lego/sys/log"

	"yunyan/lego/utils/mapstructure"
)

type Option func(*Options)
type Options struct {
	AppId     string
	SecretId  string
	SecretKey string
	SignName  string
	Template1 string
	Template2 string
}

func SetAppId(v string) Option {
	return func(o *Options) {
		o.AppId = v
	}
}

func SetSecretId(v string) Option {
	return func(o *Options) {
		o.SecretId = v
	}
}

func KeySecretKey(v string) Option {
	return func(o *Options) {
		o.SecretKey = v
	}
}

func SetSignName(v string) Option {
	return func(o *Options) {
		o.SignName = v
	}
}
func SetTemplate1(v string) Option {
	return func(o *Options) {
		o.Template1 = v
	}
}
func SetTemplate2(v string) Option {
	return func(o *Options) {
		o.Template2 = v
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
	if options.SecretId == "" || options.SecretKey == "" {
		log.Panicf("start smsverification Missing necessary configuration : Serverhost:%s Fromemail:%s Fompasswd:%s", options.SecretId, options.SecretKey)
	}
	return options
}

func newOptionsByOption(opts ...Option) Options {
	options := Options{}
	for _, o := range opts {
		o(&options)
	}
	if options.SecretId == "" || options.SecretKey == "" {
		log.Panicf("start smsverification Missing necessary configuration : Serverhost:%s Fromemail:%s Fompasswd:%s", options.SecretId, options.SecretKey)
	}
	return options
}
