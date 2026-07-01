package dify_test

import (
	"bufio"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strings"
	"testing"
	"yunyan/sys/dify"

	"github.com/go-resty/resty/v2"
)

func Test_Sys_Chat(t *testing.T) {
	apiKey := os.Getenv("DIFY_API_KEY")
	if apiKey == "" {
		t.Skip("DIFY_API_KEY env not set")
	}
	if sys, err := dify.NewSys(
		dify.SetApiKey(apiKey),
	); err != nil {
		fmt.Printf("Sys Init err:%v", err)
	} else {
		result := make(chan string)
		go func() {
			err := sys.ChatForChan("你好! 你的名字？", result)
			if err != nil {
				fmt.Printf(" err:%v", err)
				return
			}
		}()

		for v := range result {
			fmt.Printf(" result:%v", v)
		}
	}
}

func Test_Sys_Workflows(t *testing.T) {
	workflowKey := os.Getenv("DIFY_WORKFLOW_KEY")
	if workflowKey == "" {
		t.Skip("DIFY_WORKFLOW_KEY env not set")
	}

	client := resty.New()
	// Dify API 端点
	url := "https://api.dify.ai/v1/workflows/run"
	// 请求数据
	requestData := map[string]interface{}{
		"inputs": map[string]interface{}{
			"user_input": "武汉的天气如何？",
		}, // 工作流输入参数
		"response_mode": "blocking", // 响应模式
		"user":          "abc-123",  // 用户标识
	}

	// 发送 POST 请求
	resp, err := client.R().
		SetHeader("Authorization", "Bearer "+workflowKey).
		SetHeader("Content-Type", "application/json").
		SetBody(requestData).
		Post(url)

	if err != nil {
		fmt.Println("Error sending request:", err)
		return
	}

	// 打印响应
	fmt.Println("Response Status:", resp.Status())
	// fmt.Println("Response Body:", resp.String())
	wresp := &dify.WorkflowResponse{}
	err = json.Unmarshal(resp.Body(), wresp)
	fmt.Printf("Response:%+v", wresp)
}

func Test_Sys_WorkflowsForSatem(t *testing.T) {
	workflowKey := os.Getenv("DIFY_WORKFLOW_KEY")
	if workflowKey == "" {
		t.Skip("DIFY_WORKFLOW_KEY env not set")
	}
	// Dify API 端点
	url := "https://api.dify.ai/v1/workflows/run"
	// 请求数据
	requestData := map[string]interface{}{
		"inputs": map[string]interface{}{
			"user_input": "武汉的天气如何？",
		}, // 工作流输入参数
		"response_mode": "streaming", // 响应模式
		"user":          "abc-123",   // 用户标识
	}

	// 将请求数据转换为 JSON
	jsonData, err := json.Marshal(requestData)
	if err != nil {
		t.Fatalf("Error marshalling JSON: %v", err)
	}

	// 创建 HTTP 请求
	req, err := http.NewRequest("POST", url, strings.NewReader(string(jsonData)))
	if err != nil {
		t.Fatalf("Error creating request: %v", err)
	}
	req.Header.Set("Authorization", "Bearer "+workflowKey)
	req.Header.Set("Content-Type", "application/json")

	// 发送请求
	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		t.Fatalf("Error sending request: %v", err)
	}
	defer resp.Body.Close()

	defer resp.Body.Close()

	scanner := bufio.NewScanner(resp.Body)
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "data: ") {
			line = strings.TrimPrefix(line, "data: ")
			var event dify.EventData
			if err := json.Unmarshal([]byte(line), &event); err != nil {
				fmt.Printf("Error parsing JSON: %v\n", err)
				continue
			}
			parseEvent(event) // 解析不同类型的事件
		}
	}

	if err := scanner.Err(); err != nil {
		t.Fatalf("Error reading stream response: %v", err)
	}
}

// 解析数据
func parseEvent(event dify.EventData) {
	switch event.Event {
	case "workflow_started":
		var data dify.WorkflowStartedData
		if err := json.Unmarshal(event.Data, &data); err == nil {
			fmt.Printf("Workflow started: %+v\n", data)
		}

	case "node_started":
		var data dify.NodeStartedData
		if err := json.Unmarshal(event.Data, &data); err == nil {
			fmt.Printf("Node started: %+v\n", data)
		}

	case "node_finished":
		var data dify.NodeFinishedData
		if err := json.Unmarshal(event.Data, &data); err == nil {
			fmt.Printf("Node finished: %+v\n", data)
		}

	case "workflow_finished":
		var data dify.WorkflowFinishedData
		if err := json.Unmarshal(event.Data, &data); err == nil {
			fmt.Printf("Workflow finished: %+v\n", data)
		}

	case "tts_message":
		var data dify.TTSMessageData
		if err := json.Unmarshal(event.Data, &data); err == nil {
			fmt.Printf("TTS message: %+v\n", data)
		}
	default:
		fmt.Printf("Unknown event: %s\n", event.Event)
	}
}
