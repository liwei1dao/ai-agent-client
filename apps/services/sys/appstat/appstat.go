// Package appstat 提供 App 综合统计的生产者接口。
//
// 各模块调用 appstat.Incr(delta) 将统计增量序列化后推入 Redis 队列，
// 由 api 模块的 statConsumerComp 负责消费并写入 DB。
package appstat

import (
	"context"
	"yunyan/comm"
	"yunyan/lego/sys/log"
	redissys "yunyan/lego/sys/redis"
	"yunyan/pb"
	"encoding/json"
	"time"
)

const RedisQueueKey = "appstat:queue"

// TableByType 根据统计类型返回对应表名（1=日 2=月 3=年）
func TableByType(statType int32) string {
	switch statType {
	case 2:
		return comm.TableAppStatMonthly
	case 3:
		return comm.TableAppStatYearly
	default:
		return comm.TableAppStatDaily
	}
}

// Incr 将统计增量序列化后推入 Redis 队列，非阻塞。
// delta.StatDate 必须为 "2006-01-02" 格式。
func Incr(delta *pb.DBAppStat) {
	if delta.UpdateTime == 0 {
		delta.UpdateTime = time.Now().Unix()
	}
	data, err := json.Marshal(delta)
	if err != nil {
		log.Warn("appstat.Incr marshal", log.Field{Key: "err", Value: err.Error()})
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if err = redissys.Conn().LPush(ctx, redissys.RKey(RedisQueueKey), data).Err(); err != nil {
		log.Warn("appstat.Incr lpush", log.Field{Key: "err", Value: err.Error()})
	}
}
