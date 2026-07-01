package bingsearch

import (
	"yunyan/lego/sys/log"
	"yunyan/lego/utils/mapstructure"
)

type Option func(*Options)
type Options struct {
	Debug  bool //日志是否开启
	Log    log.ILogger
	ApiKey string
	Market string
}

// SetApiKey 设置微软 Bing Web Search API 的密钥
// 参数:
//   - v: API 密钥字符串
//
// 返回值:
//   - 无
//
// 异常:
//   - 无
func SetApiKey(v string) Option {
	return func(o *Options) {
		o.ApiKey = v
	}
}

// SetMarket 设置搜索市场/语言区域，如 zh-CN、en-US
// 参数:
//   - v: 市场标识
//
// 返回值:
//   - 无
//
// 异常:
//   - 无
func SetMarket(v string) Option {
	return func(o *Options) {
		o.Market = v
	}
}

// newOptions 初始化配置（从 map 与可选项合并）
// 参数:
//   - config: 配置映射
//   - opts: 可选项函数
//
// 返回值:
//   - Options: 合并后的选项
//
// 异常:
//   - 无
func newOptions(config map[string]interface{}, opts ...Option) Options {
	options := Options{}
	if config != nil {
		mapstructure.Decode(config, &options)
	}
	for _, o := range opts {
		o(&options)
	}
	if options.Log == nil {
		options.Log = log.NewTurnlog(options.Debug, log.Clone("sys.bingsearch", 3))
	}
	return options
}

// newOptionsByOption 仅基于可选项初始化配置
// 参数:
//   - opts: 可选项函数
//
// 返回值:
//   - Options: 合并后的选项
//
// 异常:
//   - 无
func newOptionsByOption(opts ...Option) Options {
	options := Options{}
	for _, o := range opts {
		o(&options)
	}
	if options.Log == nil {
		options.Log = log.NewTurnlog(options.Debug, log.Clone("sys.bingsearch", 3))
	}
	return options
}
