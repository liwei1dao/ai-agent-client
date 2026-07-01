package paypal

import (
	"yunyan/lego/sys/log"
	"yunyan/lego/utils/mapstructure"
)

type Option func(*Options)

type Options struct {
	Debug     bool
	Log       log.ILogger
	ClientID  string // PayPal Client ID
	Secret    string // PayPal Client Secret
	BaseURL   string // API Base URL, e.g. https://api-m.sandbox.paypal.com or https://api-m.paypal.com
	WebhookID string // Webhook ID for signature verification
}

func SetClientID(v string) Option  { return func(o *Options) { o.ClientID = v } }
func SetSecret(v string) Option    { return func(o *Options) { o.Secret = v } }
func SetBaseURL(v string) Option   { return func(o *Options) { o.BaseURL = v } }
func SetWebhookID(v string) Option { return func(o *Options) { o.WebhookID = v } }
func SetDebug(v bool) Option       { return func(o *Options) { o.Debug = v } }

func newOptions(config map[string]interface{}, opts ...Option) Options {
	options := Options{BaseURL: "https://api-m.sandbox.paypal.com"}
	if config != nil {
		mapstructure.Decode(config, &options)
	}
	for _, o := range opts {
		o(&options)
	}
	if options.Log == nil {
		options.Log = log.NewTurnlog(options.Debug, log.Clone("sys.paypal", 3))
	}
	return options
}

func newOptionsByOption(opts ...Option) Options {
	options := Options{BaseURL: "https://api-m.sandbox.paypal.com"}
	for _, o := range opts {
		o(&options)
	}
	if options.Log == nil {
		options.Log = log.NewTurnlog(options.Debug, log.Clone("sys.paypal", 3))
	}
	return options
}
