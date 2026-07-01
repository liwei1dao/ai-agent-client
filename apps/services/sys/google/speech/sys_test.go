package speech_test

import (
	"yunyan/sys/google/speech"
	"fmt"
	"testing"
	"time"
)

// 运行前替换为真实的服务账号 JSON 路径与 gs:// 音频地址
const (
	kGoogleSaJson = "" // 例：/Users/.../smart-bluetooth-447104-2b269474bd72.json
	kTestGsURI    = "" // 例：gs://your-bucket/your-audio.wav
)

func newTestSys(t *testing.T) speech.ISys {
	if kGoogleSaJson == "" {
		t.Skip("kGoogleSaJson is empty, skip")
	}
	sys, err := speech.NewSys(
		speech.SetJsonPath(kGoogleSaJson),
	)
	if err != nil {
		t.Fatalf("NewSys err: %v", err)
	}
	return sys
}

func Test_E2E(t *testing.T) {
	if kTestGsURI == "" {
		t.Skip("kTestGsURI is empty, skip")
	}
	sys := newTestSys(t)
	taskID, err := sys.CreateTask(kTestGsURI, "en-US", true, "")
	if err != nil {
		t.Fatalf("CreateTask err: %v", err)
	}
	fmt.Printf("CreateTask ok, taskID=%s\n", taskID)

	deadline := time.Now().Add(10 * time.Minute)
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
	t.Fatalf("task did not finish")
}

func Test_MissingKey(t *testing.T) {
	_, err := speech.NewSys()
	if err == nil {
		t.Errorf("expect error when JSON missing, got nil")
	}
}

func Test_RejectHttpURL(t *testing.T) {
	sys := newTestSys(t)
	_, err := sys.CreateTask("https://example.com/foo.wav", "en-US", false, "")
	if err == nil {
		t.Errorf("expect error for http URL, got nil")
	}
}
