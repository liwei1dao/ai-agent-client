package nats

import (
	"time"

	gonats "github.com/nats-io/nats.go"
)

func newSys(options *Options) (sys *natsSys, err error) {
	sys = &natsSys{options: options}
	if err = sys.init(); err != nil {
		return nil, err
	}
	return
}

type natsSys struct {
	options *Options
	conn    *gonats.Conn
	js      gonats.JetStreamContext
}

func (this *natsSys) init() (err error) {
	this.conn, err = gonats.Connect(this.options.URL,
		gonats.MaxReconnects(this.options.MaxReconnects),
		gonats.ReconnectWait(time.Duration(this.options.ReconnectWait)*time.Second),
		gonats.Name(this.options.Name),
		gonats.DisconnectErrHandler(func(_ *gonats.Conn, e error) {
			this.options.Log.Warnf("sys.nats 连接断开: %v", e)
		}),
		gonats.ReconnectHandler(func(c *gonats.Conn) {
			this.options.Log.Infof("sys.nats 已重连: %s", c.ConnectedUrl())
		}),
	)
	if err != nil {
		return
	}
	if this.js, err = this.conn.JetStream(); err != nil {
		this.conn.Close()
		return
	}
	this.options.Log.Infof("sys.nats 连接成功: %s", this.options.URL)
	return
}

func (this *natsSys) Conn() *gonats.Conn { return this.conn }

func (this *natsSys) JetStream() gonats.JetStreamContext { return this.js }

func (this *natsSys) Publish(subject string, data []byte) error {
	_, err := this.js.Publish(subject, data)
	return err
}

func (this *natsSys) PublishAsync(subject string, data []byte) error {
	_, err := this.js.PublishAsync(subject, data)
	return err
}

func (this *natsSys) Close() {
	if this.conn != nil {
		_ = this.conn.Drain()
	}
}
