package postgres

import (
	"time"

	"yunyan/lego/sys/log"
	"yunyan/lego/utils/mapstructure"
)

type Option func(*Options)
type Options struct {
	Debug       bool //日志是否开启
	Log         log.ILogger
	Dsn         string //PostgreSQL DSN（postgres:// 或 postgresql://）
	ReadDsn     string //只读副本 DSN；非空时启用读写分离：读走副本、写走主库。空则单库
	MaxPoolSize uint64
	TimeOut     time.Duration
}

func SetDsn(v string) Option {
	return func(o *Options) {
		o.Dsn = v
	}
}
func SetReadDsn(v string) Option {
	return func(o *Options) {
		o.ReadDsn = v
	}
}
func SetMaxPoolSize(v uint64) Option {
	return func(o *Options) {
		o.MaxPoolSize = v
	}
}
func SetTimeOut(v time.Duration) Option {
	return func(o *Options) {
		o.TimeOut = v
	}
}

func newOptions(config map[string]interface{}, opts ...Option) Options {
	options := Options{
		MaxPoolSize: 5, // Supabase pooler 连接数有限，默认保守；多服务进程共享配额（务必让 进程数×实例数×本值 远小于 pooler 上限）
		TimeOut:     time.Second * 3,
	}
	if config != nil {
		mapstructure.Decode(config, &options)
	}
	for _, o := range opts {
		o(&options)
	}
	if options.Log == nil {
		options.Log = log.NewTurnlog(options.Debug, log.Clone("sys.postgres", 3))
	}
	return options
}

func newOptionsByOption(opts ...Option) Options {
	options := Options{
		MaxPoolSize: 5, // Supabase pooler 连接数有限，默认保守；多服务进程共享配额（务必让 进程数×实例数×本值 远小于 pooler 上限）
		TimeOut:     time.Second * 3,
	}
	for _, o := range opts {
		o(&options)
	}
	if options.Log == nil {
		options.Log = log.NewTurnlog(options.Debug, log.Clone("sys.postgres", 3))
	}
	return options
}
