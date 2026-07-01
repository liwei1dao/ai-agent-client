package translate

import (
	"yunyan/lego/sys/log"
	"yunyan/lego/utils/mapstructure"
)

type Option func(*Options)

type Options struct {
	Debug       bool
	Log         log.ILogger
	JsonPath    string // 服务账号密钥 JSON 文件路径
	JsonContent []byte // 服务账号密钥 JSON 内容（与 JsonPath 二选一）
	ProjectId   string // GCP 项目 ID，留空则从 JSON 中读取
	Location    string // 模型位置，默认 global
	Timeout     int    // HTTP 超时（秒），默认 30
}

func SetJsonPath(v string) Option {
	return func(o *Options) {
		o.JsonPath = v
	}
}

func SetJsonContent(v []byte) Option {
	return func(o *Options) {
		o.JsonContent = v
	}
}

func SetProjectId(v string) Option {
	return func(o *Options) {
		o.ProjectId = v
	}
}

func SetLocation(v string) Option {
	return func(o *Options) {
		o.Location = v
	}
}

func SetTimeout(v int) Option {
	return func(o *Options) {
		o.Timeout = v
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
	applyDefaults(&options)
	return options
}

func newOptionsByOption(opts ...Option) Options {
	options := Options{}
	for _, o := range opts {
		o(&options)
	}
	applyDefaults(&options)
	return options
}

func applyDefaults(o *Options) {
	if o.Location == "" {
		o.Location = "global"
	}
	if o.Timeout <= 0 {
		o.Timeout = 30
	}
	if o.Log == nil {
		o.Log = log.NewTurnlog(o.Debug, log.Clone("sys.google.translate", 3))
	}
}
