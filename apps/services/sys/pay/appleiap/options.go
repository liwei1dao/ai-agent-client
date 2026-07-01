package appleiap

import (
	"yunyan/lego/sys/log"
	"yunyan/lego/utils/mapstructure"
)

type Options struct {
	Debug        bool
	Log          log.ILogger
	SharedSecret string // App 内购订阅共享密钥（用于 legacy verifyReceipt 校验订阅）
	UseSandbox   bool   // 仅用于强制走 sandbox；通常自动按 21007 回退
	// App Store Server API 凭据（用于 VerifyTransaction）
	AppStoreIssuerID      string // App Store Connect Issuer ID
	AppStoreKeyID         string // App Store Connect Key ID (kid)
	AppStorePrivateKeyPEM string // App Store Connect API Key (.p8) 原始内容
	AppStoreBundleID      string // 目标应用的 bundleId（StoreKit inApps 必须在 JWT 载荷中携带 bid）
}

type Option func(*Options)

func SetDebug(v bool) Option {
	return func(o *Options) { o.Debug = v }
}

func SetLog(l log.ILogger) Option {
	return func(o *Options) { o.Log = l }
}

func SetSharedSecret(secret string) Option {
	return func(o *Options) { o.SharedSecret = secret }
}

func SetUseSandbox(v bool) Option {
	return func(o *Options) { o.UseSandbox = v }
}

// App Store Server API 选项设置
func SetAppStoreIssuerID(v string) Option {
	return func(o *Options) { o.AppStoreIssuerID = v }
}

func SetAppStoreKeyID(v string) Option {
	return func(o *Options) { o.AppStoreKeyID = v }
}

func SetAppStorePrivateKeyPEM(v string) Option {
	return func(o *Options) { o.AppStorePrivateKeyPEM = v }
}

// StoreKit inApps 需要在 JWT 载荷中包含 bid（bundleId）以通过授权
func SetAppStoreBundleID(v string) Option {
	return func(o *Options) { o.AppStoreBundleID = v }
}

func newOptions(config map[string]interface{}, opts ...Option) Options {
	options := Options{}
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
	options := Options{}
	for _, o := range opts {
		o(&options)
	}
	if options.Log == nil {
		options.Log = log.NewTurnlog(options.Debug, log.Clone("sys.paypal", 3))
	}
	return options
}
