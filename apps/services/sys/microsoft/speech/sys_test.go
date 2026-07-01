package speech_test

import (
	"yunyan/sys/microsoft/speech"
	"fmt"
	"testing"
	"time"
)

// 注意：以下凭据为占位，运行前替换为有效的 Azure Speech 订阅
const (
	kAzureSpeechKey    = "" // Azure Speech 订阅 Key
	kAzureSpeechRegion = "eastus"
	kTestAudioURL      = "" // 公网可访问的音频 URL（wav/mp3 等）
)

func newTestSys(t *testing.T) speech.ISys {
	if kAzureSpeechKey == "" {
		t.Skip("kAzureSpeechKey is empty, skip")
	}
	sys, err := speech.NewSys(
		speech.SetKey(kAzureSpeechKey),
		speech.SetRegion(kAzureSpeechRegion),
	)
	if err != nil {
		t.Fatalf("NewSys err: %v", err)
	}
	return sys
}

// 端到端：提交 → 轮询 → 拿结果
func Test_E2E(t *testing.T) {
	if kTestAudioURL == "" {
		t.Skip("kTestAudioURL is empty, skip")
	}
	sys := newTestSys(t)

	taskID, err := sys.CreateTask(kTestAudioURL, "en-US", true, "")
	if err != nil {
		t.Fatalf("CreateTask err: %v", err)
	}
	fmt.Printf("CreateTask ok, taskID=%s\n", taskID)

	deadline := time.Now().Add(5 * time.Minute)
	for time.Now().Before(deadline) {
		status, contexts, err := sys.QueryTask(taskID)
		if err != nil {
			t.Fatalf("QueryTask err: %v", err)
		}
		fmt.Printf("status=%s sentences=%d\n", status, len(contexts))
		if status == speech.StatusSuccess {
			for i, c := range contexts {
				if i > 5 {
					break
				}
				fmt.Printf("  [%s %d-%d] %s\n", c.Speaker, c.StartTime, c.EndTime, c.Content)
			}
			return
		}
		if status == speech.StatusFailed {
			t.Fatalf("task failed")
		}
		time.Sleep(15 * time.Second)
	}
	t.Fatalf("task did not finish in 5min")
}

// 缺 Key 时应直接报错
func Test_MissingKey(t *testing.T) {
	_, err := speech.NewSys(speech.SetRegion("eastus"))
	if err == nil {
		t.Errorf("expect error when Key missing, got nil")
	}
}

// 缺 Region/Endpoint 时应直接报错
func Test_MissingEndpoint(t *testing.T) {
	_, err := speech.NewSys(speech.SetKey("xxx"))
	if err == nil {
		t.Errorf("expect error when Region/Endpoint missing, got nil")
	}
}

// OnInit 包级路径
func Test_OnInit(t *testing.T) {
	if kAzureSpeechKey == "" {
		t.Skip("kAzureSpeechKey is empty, skip")
	}
	err := speech.OnInit(map[string]interface{}{
		"Key":    kAzureSpeechKey,
		"Region": kAzureSpeechRegion,
	})
	if err != nil {
		t.Fatalf("OnInit err: %v", err)
	}
}
