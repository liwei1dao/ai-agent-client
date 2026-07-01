package nats

import (
	"os"
	"testing"
	"time"
)

// TestNatsConnect 对真实 NATS 服务端做连通性诊断。
//
// 默认跳过；设置环境变量 NATS_URL 才运行——避免无 NATS 的环境(如 CI、本机)误失败。
//
// 用法：
//
//	NATS_URL=nats://47.253.88.66:4222 go test -v -run TestNatsConnect ./sys/nats/
//
// 它走和 home 启动时完全一样的路径：OnInit(连接 + 取 JetStream 上下文)，
// 再用 core 发布 + flush 证明不仅连得上、还能真正把数据发到服务端。
func TestNatsConnect(t *testing.T) {
	url := os.Getenv("NATS_URL")
	if url == "" {
		t.Skip("未设置 NATS_URL，跳过。示例: NATS_URL=nats://47.253.88.66:4222 go test -v -run TestNatsConnect ./sys/nats/")
	}

	t.Logf("→ 连接 %s ...", url)
	start := time.Now()
	if err := OnInit(map[string]interface{}{
		"URL":           url,
		"MaxReconnects": 0, // 一次性诊断，不重连
		"Name":          "natscheck-test",
	}); err != nil {
		t.Fatalf("✗ OnInit 失败 (%s): %v\n  dial/timeout 多半是网络/安全组/容器 hairpin；auth 错才是账号问题",
			time.Since(start).Round(time.Millisecond), err)
	}

	conn := Conn()
	if conn == nil {
		t.Fatal("✗ Conn() 为 nil（连接未建立）")
	}
	defer conn.Close()
	t.Logf("✓ 已连接 %s (耗时 %s, 服务端 name=%s)",
		conn.ConnectedUrl(), time.Since(start).Round(time.Millisecond), conn.ConnectedServerName())

	if JetStream() == nil {
		t.Fatal("✗ JetStream 上下文为 nil")
	}
	t.Log("✓ JetStream 上下文 OK")

	const subject = "natscheck.ping"
	if err := conn.Publish(subject, []byte("ping")); err != nil {
		t.Fatalf("✗ 发布失败: %v", err)
	}
	if err := conn.FlushTimeout(5 * time.Second); err != nil {
		t.Fatalf("✗ flush 失败(发出去但服务端没确认): %v", err)
	}
	t.Logf("✓ 发布 + flush OK (subject=%s)", subject)
	t.Log("全部通过：NATS 可连、可发布")
}
