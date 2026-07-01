package redis

import "github.com/redis/go-redis/v9"

/*
系统描述:Redis 驱动系统（与 lego/sys/mysql、lego/sys/postgres 平级）。
全局单例：OnInit 后通过包级函数 Conn()/RKey() 调用。
*/
type (
	ISys interface {
		Conn() redis.UniversalClient // 原生客户端，供 Pipelined/HGetAll/PFCount 等直接调用
		RKey(key string) string      // 给 key 加应用前缀，返回 "前缀:key"
	}
)

var defsys ISys

func OnInit(config map[string]interface{}, option ...Option) (err error) {
	defsys, err = newSys(newOptions(config, option...))
	return
}

func NewSys(option ...Option) (sys ISys, err error) {
	sys, err = newSys(newOptionsByOption(option...))
	return
}

// Conn 返回全局 Redis 客户端。
func Conn() redis.UniversalClient {
	return defsys.Conn()
}

// RKey 给 key 加全局前缀。
func RKey(key string) string {
	return defsys.RKey(key)
}
