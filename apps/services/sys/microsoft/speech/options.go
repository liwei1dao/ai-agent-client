package speech

import (
	"yunyan/lego/sys/log"
	"yunyan/lego/utils/mapstructure"
)

type Option func(*Options)

// Options Azure Speech Batch Transcription 配置
//
// Endpoint 与 Region 二选一即可：
//   - 提供 Endpoint：直接使用，如 https://eastus.api.cognitive.microsoft.com
//   - 仅提供 Region：自动拼装为 https://{region}.api.cognitive.microsoft.com
type Options struct {
	Debug    bool
	Log      log.ILogger
	Key      string // Azure Speech 订阅 Key
	Region   string // 资源区域，如 eastus / southeastasia
	Endpoint string // 完整 endpoint（不含路径）
}

func SetKey(v string) Option {
	return func(o *Options) {
		o.Key = v
	}
}

func SetRegion(v string) Option {
	return func(o *Options) {
		o.Region = v
	}
}

func SetEndpoint(v string) Option {
	return func(o *Options) {
		o.Endpoint = v
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
	if options.Log == nil {
		options.Log = log.NewTurnlog(options.Debug, log.Clone("sys.microsoft.speech", 3))
	}
	return options
}

func newOptionsByOption(opts ...Option) Options {
	options := Options{}
	for _, o := range opts {
		o(&options)
	}
	if options.Log == nil {
		options.Log = log.NewTurnlog(options.Debug, log.Clone("sys.microsoft.speech", 3))
	}
	return options
}
