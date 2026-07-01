package api

import (
	"yunyan/modules"

	"yunyan/lego/utils/mapstructure"
)

type (
	Options struct {
		modules.Options
		TokenKey      string
		AdninAccount  string //web引擎日志开关
		AdninPassword string //websocket 监听端口
		ConsolePort   int    //控制台HTTP端口
		SiteName      string //后台站点名称（不同环境可在配置中区分）
		CurrencyType  int32  //货币类型：0=人民币(元) 1=美元(USD)
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
	return
}
