package cache

/*
通用 Redis 缓存层：基于 Redis Hash 的"全量数据集"缓存。

一个数据集 = 一个 Redis Hash（key = redissys.RKey(name)，field = 主键字符串，value = JSON）。
适合"管理后台维护、低频变更、高频读取"的引用数据（如 product），配合
全量预热 + 定时刷新 + 事件驱动刷新使用，使读请求恒命中 Redis。

复用 lego/sys/redis 已初始化的客户端(redissys.Conn)与统一 key 前缀(redissys.RKey)。
*/

import (
	"context"
	"encoding/json"
	"time"

	redissys "yunyan/lego/sys/redis"

	"github.com/redis/go-redis/v9"
)

// ReplaceAll 用全量数据原子替换某数据集缓存。
// 使用事务管道（MULTI/EXEC）依次执行 DEL + HSET + EXPIRE，对读者不可见中间态，刷新无空窗。
// items 的 key 为主键字符串，value 为任意可 json.Marshal 的对象；items 为空时仅清空该数据集。
func ReplaceAll(ctx context.Context, name string, items map[string]any, ttl time.Duration) (err error) {
	key := redissys.RKey(name)
	fields := make(map[string]any, len(items))
	for f, v := range items {
		var b []byte
		if b, err = json.Marshal(v); err != nil {
			return
		}
		fields[f] = b
	}
	pipe := redissys.Conn().TxPipeline()
	pipe.Del(ctx, key)
	if len(fields) > 0 {
		pipe.HSet(ctx, key, fields)
		if ttl > 0 {
			pipe.Expire(ctx, key, ttl)
		}
	}
	_, err = pipe.Exec(ctx)
	return
}

// GetOne 按主键取单条；缓存中不存在该 field 时返回 (nil, false, nil)。
func GetOne[T any](ctx context.Context, name, field string) (v *T, found bool, err error) {
	var b []byte
	if b, err = redissys.Conn().HGet(ctx, redissys.RKey(name), field).Bytes(); err != nil {
		if err == redis.Nil {
			err = nil
		}
		return
	}
	v = new(T)
	if err = json.Unmarshal(b, v); err != nil {
		v = nil
		return
	}
	found = true
	return
}

// GetAll 取整个数据集；缓存为空时返回空切片。
func GetAll[T any](ctx context.Context, name string) (list []*T, err error) {
	var m map[string]string
	if m, err = redissys.Conn().HGetAll(ctx, redissys.RKey(name)).Result(); err != nil {
		return
	}
	list = make([]*T, 0, len(m))
	for _, s := range m {
		v := new(T)
		if err = json.Unmarshal([]byte(s), v); err != nil {
			list = nil
			return
		}
		list = append(list, v)
	}
	return
}
