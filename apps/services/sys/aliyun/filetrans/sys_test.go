package filetrans_test

import (
	"fmt"
	"os"
	"testing"
	"time"
	"yunyan/sys/aliyun/filetrans"
)

var testApiKey = os.Getenv("ALIYUN_DASHSCOPE_API_KEY")

func TestCreateTask(t *testing.T) {
	if testApiKey == "" {
		t.Skip("ALIYUN_DASHSCOPE_API_KEY env not set")
	}
	sys, err := filetrans.NewSys(
		filetrans.SetApiKey(testApiKey),
	)
	if err != nil {
		t.Fatalf("初始化失败: %v", err)
	}

	taskID, err := sys.CreateTask(
		"https://deepsound-1253517901.cos.ap-guangzhou.myqcloud.com/User/1942916924698525696/LocalAudio/2026/02/27/jLEIQzYIAnqy.wav",
		"vi-VN",
		true,
		"",
	)
	if err != nil {
		t.Fatalf("创建任务失败: %v", err)
	}
	fmt.Printf("创建任务成功: taskID=%s\n", taskID)
}

func TestQueryTask(t *testing.T) {
	if testApiKey == "" {
		t.Skip("ALIYUN_DASHSCOPE_API_KEY env not set")
	}
	sys, err := filetrans.NewSys(
		filetrans.SetApiKey(testApiKey),
	)
	if err != nil {
		t.Fatalf("初始化失败: %v", err)
	}

	// 替换为 TestCreateTask 返回的实际 taskID
	taskID := "1c09487e-9e92-4c4d-ba62-a442bacfc309"

	status, contexts, err := sys.QueryTask(taskID)
	if err != nil {
		t.Fatalf("查询失败: %v", err)
	}
	fmt.Printf("查询结果: status=%s\n", status)
	for i, ctx := range contexts {
		fmt.Printf("  [%d] %dms-%dms Speaker(%s): %s\n", i, ctx.StartTime, ctx.EndTime, ctx.Speaker, ctx.Content)
	}
}

func TestCreateAndPollTask(t *testing.T) {
	if testApiKey == "" {
		t.Skip("ALIYUN_DASHSCOPE_API_KEY env not set")
	}
	sys, err := filetrans.NewSys(
		filetrans.SetApiKey(testApiKey),
	)
	if err != nil {
		t.Fatalf("初始化失败: %v", err)
	}

	taskID, err := sys.CreateTask(
		"https://deepsound-1253517901.cos.ap-guangzhou.myqcloud.com/User/2014183956768882688/LocalAudio/2026/01/22/kUqCZgiVkspH.wav",
		"zh",
		true,
		"",
	)
	if err != nil {
		t.Fatalf("创建任务失败: %v", err)
	}
	fmt.Printf("任务已提交: taskID=%s\n", taskID)

	for i := 0; i < 60; i++ {
		time.Sleep(5 * time.Second)
		status, contexts, err := sys.QueryTask(taskID)
		fmt.Printf("  轮询 #%d: status=%s\n", i+1, status)
		if err != nil {
			t.Fatalf("查询失败: %v", err)
		}
		if status == filetrans.StatusSuccess {
			fmt.Printf("转写完成，共 %d 条结果:\n", len(contexts))
			for j, ctx := range contexts {
				fmt.Printf("  [%d] %dms-%dms Speaker(%s): %s\n", j, ctx.StartTime, ctx.EndTime, ctx.Speaker, ctx.Content)
			}
			return
		}
		if status == filetrans.StatusFailed {
			t.Fatalf("任务失败")
		}
	}
	t.Fatal("超时：任务未在 5 分钟内完成")
}
