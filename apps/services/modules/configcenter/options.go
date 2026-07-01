package configcenter

import (
	"yunyan/lego/utils/mapstructure"
	"yunyan/modules"
)

type (
	HTTPOptions struct {
		Addr string // 监听地址，如 ":8091"
	}

	Options struct {
		modules.Options
		HTTP      HTTPOptions
		SecretEnv string // 加密密钥所在的环境变量名，默认 CONFIG_SECRET_KEY
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
		this.HTTP.Addr = ":8091"
	}
	if this.SecretEnv == "" {
		this.SecretEnv = "CONFIG_SECRET_KEY"
	}
	return
}
