package redis

import (
	"context"
	"crypto/tls"

	"github.com/redis/go-redis/v9"
)

func newSys(options Options) (sys *Redis, err error) {
	sys = &Redis{options: options}
	err = sys.init()
	return
}

type Redis struct {
	options Options
	client  redis.UniversalClient
}

func (this *Redis) init() (err error) {
	opt := &redis.UniversalOptions{
		Addrs:    this.options.Addr,
		Password: this.options.Password,
		DB:       this.options.DB,
	}
	if this.options.TLS {
		opt.TLSConfig = &tls.Config{}
	}
	this.client = redis.NewUniversalClient(opt)
	// 启动即 Ping，连不上直接报错（Redis 为必备依赖）。
	if err = this.client.Ping(context.Background()).Err(); err != nil {
		this.options.Log.Errorln(err)
		return
	}
	return
}

func (this *Redis) Conn() redis.UniversalClient {
	return this.client
}

func (this *Redis) RKey(key string) string {
	if this.options.KeyPrefix == "" {
		return key
	}
	return this.options.KeyPrefix + ":" + key
}
