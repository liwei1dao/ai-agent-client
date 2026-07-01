// Package nats 是 NATS / JetStream 的系统级封装，遵循 sys/ 子系统惯例：
// OnInit(config) 全局初始化一次，之后通过包级函数（Conn / JetStream / Publish）取用。
//
// 只负责连接与发布/订阅入口；Stream 创建、消费者等业务逻辑由调用方持有 JetStream 上下文自行处理。
package nats

import (
	"errors"

	gonats "github.com/nats-io/nats.go"
)

// ErrNotReady 表示 NATS 尚未初始化（OnInit 未成功）。
var ErrNotReady = errors.New("sys.nats: 未初始化")

type ISys interface {
	Conn() *gonats.Conn                 // 原始连接
	JetStream() gonats.JetStreamContext // JetStream 上下文
	Publish(subject string, data []byte) error      // 同步发布（等待 ack）
	PublishAsync(subject string, data []byte) error // 异步发布（不等 ack，高吞吐）
	Close()                             // 优雅关闭（Drain）
}

var defsys ISys

// OnInit 初始化全局 NATS 连接。连接失败返回 err 且不设置 defsys，
// 由调用方决定是否容错（如 ops 服务记录告警后继续，待 NATS 就绪重启）。
func OnInit(config map[string]interface{}, opt ...Option) (err error) {
	var options *Options
	if options, err = newOptions(config, opt...); err != nil {
		return
	}
	defsys, err = newSys(options)
	return
}

// NewSys 创建一个独立的 NATS 实例（不写入全局 defsys）。
func NewSys(opt ...Option) (sys ISys, err error) {
	var options *Options
	if options, err = newOptions(nil, opt...); err != nil {
		return
	}
	return newSys(options)
}

// Conn 返回全局连接；未初始化时返回 nil。
func Conn() *gonats.Conn {
	if defsys == nil {
		return nil
	}
	return defsys.Conn()
}

// JetStream 返回全局 JetStream 上下文；未初始化时返回 nil。
func JetStream() gonats.JetStreamContext {
	if defsys == nil {
		return nil
	}
	return defsys.JetStream()
}

// Publish 同步发布（等待 JetStream ack）。未初始化返回 ErrNotReady。
func Publish(subject string, data []byte) error {
	if defsys == nil {
		return ErrNotReady
	}
	return defsys.Publish(subject, data)
}

// PublishAsync 异步发布（不等 ack）。适合高频埋点等非阻塞场景。未初始化返回 ErrNotReady。
func PublishAsync(subject string, data []byte) error {
	if defsys == nil {
		return ErrNotReady
	}
	return defsys.PublishAsync(subject, data)
}

// Close 关闭全局连接。
func Close() {
	if defsys != nil {
		defsys.Close()
	}
}
