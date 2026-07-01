package dify

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strings"
	"time"
)

func newSys(options Options) (sys *Dify, err error) {
	sys = &Dify{
		options: options,
	}
	return
}

type Dify struct {
	options Options
}

func (this *Dify) ChatForChan(msg string, result chan string) (err error) {
	var (
		body  []byte
		line  []byte
		value string
	)
	// 创建带超时的 context（建议 5-10 分钟，根据实际需求调整）
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()

	requestBody := ChatMessageRequest{
		Inputs:         make(map[string]interface{}),
		Query:          msg,
		ResponseMode:   "streaming",
		ConversationID: "",
		User:           "abc-123",
		// Files: []File{
		// 	{
		// 		Type:           "image",
		// 		TransferMethod: "remote_url",
		// 		URL:            "https://cloud.dify.ai/logo/logo-site.png",
		// 	},
		// },
	}

	body, err = json.Marshal(requestBody)
	if err != nil {
		return
	}

	req, _ := http.NewRequestWithContext(ctx, "POST", baseurl, bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+this.options.ApiKey)
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{
		Timeout: 0, // 禁用客户端超时，使用 context 控制
	}

	resp, err := client.Do(req)
	if err != nil {
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		err = fmt.Errorf("code == %d", resp.StatusCode)
	}

	// 流式读取核心逻辑
	reader := bufio.NewReader(resp.Body)
	for {
		select {
		case <-ctx.Done():
			log.Println("上下文超时或取消")
			return
		default:
			// 读取直到遇到 \n\n（SSE 事件分隔符）
			line, err = reader.ReadBytes('\n')
			if err != nil {
				if err.Error() == "EOF" {
					close(result)
					return
				}
				return
			}

			// 清理数据行
			line = bytes.TrimSpace(line)
			if len(line) == 0 {
				continue
			}

			// 处理 SSE 格式
			if bytes.HasPrefix(line, []byte("data: ")) {
				data := bytes.TrimPrefix(line, []byte("data: "))
				if value, err = handleEvent(data); err == nil {
					result <- value
				}
			}
		}
	}
}

func handleEvent(data []byte) (result string, err error) {
	var base BaseEvent
	if err = json.Unmarshal(data, &base); err != nil {
		// fmt.Printf("Error parsing base event: %v", err)
		return
	}

	switch base.Event {
	case "message":
		var msg MessageEvent
		if err = json.Unmarshal(data, &msg); err != nil {
			// fmt.Printf("Error parsing message event: %v", err)
			return
		}
		result = msg.Answer
		// fmt.Printf("[MSG] %s", msg.Answer)
	case "message_end":
		var end MessageEndEvent
		if err = json.Unmarshal(data, &end); err != nil {
			// fmt.Printf("Error parsing message_end event: %v", err)
			return
		}
		// fmt.Printf("\n[END] Usage: %+v", end.Metadata.Usage)

	case "tts_message":
		var tts TTSMessageEvent
		if err = json.Unmarshal(data, &tts); err != nil {
			// fmt.Printf("Error parsing tts_message event: %v", err)
			return
		}
		// 处理音频数据（base64 解码等）
		// fmt.Printf("[TTS] Received audio chunk (%d bytes)\n", len(tts.Audio))

	case "tts_message_end":
		var ttsEnd TTSMessageEndEvent
		if err = json.Unmarshal(data, &ttsEnd); err != nil {
			// fmt.Printf("Error parsing tts_message_end event: %v", err)
			return
		}
		// fmt.Println("[TTS END] Audio stream completed")
	default:
		// fmt.Printf("Unknown event type: %s", base.Event)
	}
	return
}

func (this *Dify) Workflows(msg string, result chan string) (err error) {
	var (
		jsonData []byte
		req      *http.Request
	)
	defer close(result)
	// 请求数据
	requestData := map[string]interface{}{
		"inputs": map[string]interface{}{
			"user_input": msg,
		}, // 工作流输入参数
		"response_mode": "streaming", // 响应模式
		"user":          "abc-123",   // 用户标识
	}

	// 将请求数据转换为 JSON
	jsonData, err = json.Marshal(requestData)
	if err != nil {
		return
	}

	// 创建 HTTP 请求
	req, err = http.NewRequest("POST", workflowsurl, strings.NewReader(string(jsonData)))
	if err != nil {
		return
	}
	req.Header.Set("Authorization", "Bearer app-Dh6RBY4u4G8Kfk4l9sle1UPl")
	req.Header.Set("Content-Type", "application/json")

	// 发送请求
	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return
	}
	defer resp.Body.Close()
	scanner := bufio.NewScanner(resp.Body)
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "data: ") {
			line = strings.TrimPrefix(line, "data: ")
			result <- line
		}
	}
	if err = scanner.Err(); err != nil {
		return
	}
	return
}
