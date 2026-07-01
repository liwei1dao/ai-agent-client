package speech

import (
	"yunyan/lego/sys/log"
	"yunyan/lego/utils/mapstructure"
)

type Option func(*Options)

type Options struct {
	Debug             bool
	Log               log.ILogger
	JsonPath          string // 服务账号密钥 JSON 文件路径
	JsonContent       []byte // 服务账号密钥 JSON 内容（与 JsonPath 二选一）
	ProjectId         string // GCP 项目 ID，留空则从 JSON 中读取
	SampleRateHertz   int    // 采样率，留空（=0）由 Google 自动探测
	Encoding          string // 编码：LINEAR16 / FLAC / MP3 / OGG_OPUS / 留空让 Google 自动识别
	DiarizationMin    int    // 说话人最少数（>=2 启用分离），默认 2
	DiarizationMax    int    // 说话人最多数，默认 6
	Timeout           int    // HTTP 超时（秒），默认 60
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

func SetSampleRateHertz(v int) Option {
	return func(o *Options) {
		o.SampleRateHertz = v
	}
}

func SetEncoding(v string) Option {
	return func(o *Options) {
		o.Encoding = v
	}
}

func SetDiarizationMin(v int) Option {
	return func(o *Options) {
		o.DiarizationMin = v
	}
}

func SetDiarizationMax(v int) Option {
	return func(o *Options) {
		o.DiarizationMax = v
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
	if o.DiarizationMin <= 0 {
		o.DiarizationMin = 2
	}
	if o.DiarizationMax <= 0 {
		o.DiarizationMax = 6
	}
	if o.Timeout <= 0 {
		o.Timeout = 60
	}
	if o.Log == nil {
		o.Log = log.NewTurnlog(o.Debug, log.Clone("sys.google.speech", 3))
	}
}
