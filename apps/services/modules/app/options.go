package app

import (
	"yunyan/lego/utils/mapstructure"
	"yunyan/modules"
)

type (
	HTTPOptions struct {
		Addr string // 监听地址，如 ":8090"
	}

	Options struct {
		modules.Options
		HTTP     HTTPOptions
		TokenKey string // JWT 签名密钥
		CodeTTL  int    // 验证码有效期（秒），默认 300
	}
)

func (this *Options) LoadConfig(settings map[string]interface{}) (err error) {
	if settings != nil {
		if err = this.Options.LoadConfig(settings); err != nil {
			return
		}
		if err = mapstructure.Decode(settings, this); err != nil {
			return
		}
	}
	if this.HTTP.Addr == "" {
		this.HTTP.Addr = ":8090"
	}
	if this.TokenKey == "" {
		this.TokenKey = "app-dev-secret-key"
	}
	if this.CodeTTL <= 0 {
		this.CodeTTL = 300
	}
	return
}
