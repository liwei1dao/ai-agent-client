package console

import (
	"yunyan/lego/utils/mapstructure"
	"yunyan/modules"
)

type (
	// HTTPOptions HTTP 监听配置。
	HTTPOptions struct {
		Addr string // 监听地址，如 ":8080"
	}

	// Options console 模块配置（对应 console.yaml 的 modules.console 块）。
	Options struct {
		modules.Options
		HTTP          HTTPOptions
		StaticDir     string // SPA 静态目录，默认 ./consoleweb
		TokenKey      string // JWT 签名密钥
		AdminAccount  string // 引导超管账号
		AdminPassword string // 引导超管密码
		SiteName      string // 站点名称
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
		this.HTTP.Addr = ":8080"
	}
	if this.StaticDir == "" {
		this.StaticDir = "./consoleweb"
	}
	if this.TokenKey == "" {
		this.TokenKey = "console-dev-secret-key"
	}
	if this.AdminAccount == "" {
		this.AdminAccount = "admin"
	}
	return
}
