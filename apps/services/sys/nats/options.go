package nats

import (
	"errors"

	"yunyan/lego/sys/log"
	"yunyan/lego/utils/mapstructure"
)

type Option func(*Options)

// Options sys.nats 连接配置（对应 yaml 的 sys.nats）。
// 只管连接层；Stream / Subject / 消费者等业务概念由调用方（如 ops 模块）持有。
type Options struct {
	URL           string // nats://host:4222（多地址逗号分隔）
	MaxReconnects int    // 最大重连次数，默认 -1（无限）
	ReconnectWait int    // 重连间隔(秒)，默认 2
	Name          string // 连接名，便于在 NATS 端识别
	Debug         bool
	Log           log.ILogger
}

func SetDebug(v bool) Option { return func(o *Options) { o.Debug = v } }
func SetLog(v log.ILogger) Option {
	return func(o *Options) { o.Log = v }
}

func newOptions(config map[string]interface{}, opts ...Option) (options *Options, err error) {
	options = &Options{
		MaxReconnects: -1,
		ReconnectWait: 2,
	}
	if config != nil {
		if err = mapstructure.Decode(config, options); err != nil {
			return
		}
	}
	for _, o := range opts {
		o(options)
	}
	if options.URL == "" {
		return nil, errors.New("sys.nats: url 为空")
	}
	if options.Log = log.NewTurnlog(options.Debug, log.Clone("sys.nats", 3)); options.Log == nil {
		err = errors.New("log is nil")
	}
	return
}
