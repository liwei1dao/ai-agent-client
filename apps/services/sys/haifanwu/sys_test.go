package haifanwu_test

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net/http"
	"testing"
	"time"
)

// 配置参数（从控制台获取）
const (
	APIKey    = "your_api_key"
	APISecret = "your_api_secret"
	APIURL    = "https://api.example.com/v1/tts" // 请替换为真实API地址
)

// 请求结构体（根据文档调整字段）
type TTSRequest struct {
	Text     string `json:"text"`
	Language string `json:"language,omitempty"`
	Voice    string `json:"voice,omitempty"`
	Speed    int    `json:"speed,omitempty"`
}

// 响应结构体（根据文档调整字段）
type TTSResponse struct {
	Code    int    `json:"code"`
	Message string `json:"msg"`
	Data    struct {
		AudioURL string `json:"audio_url"`
		Duration int    `json:"duration"`
	} `json:"data"`
}

func Test_Sys(t *testing.T) {
	// 创建请求体
	requestBody := TTSRequest{
		Text:     "你好，欢迎使用语音合成服务",
		Language: "zh-CN",
		Voice:    "female-1",
		Speed:    5,
	}

	// 调用API
	response, err := CallTTSAPI(requestBody)
	if err != nil {
		fmt.Println("API调用失败:", err)
		return
	}

	// 处理响应
	if response.Code == 0 {
		fmt.Printf("合成成功！音频地址：%s 时长：%dms\n",
			response.Data.AudioURL,
			response.Data.Duration)
	} else {
		fmt.Printf("合成失败：%s\n", response.Message)
	}
}

// 调用API核心方法
func CallTTSAPI(reqBody TTSRequest) (*TTSResponse, error) {
	// 序列化请求体
	jsonBody, err := json.Marshal(reqBody)
	if err != nil {
		return nil, err
	}

	// 创建HTTP客户端
	client := &http.Client{Timeout: 10 * time.Second}

	// 创建请求
	req, err := http.NewRequest("POST", APIURL, bytes.NewBuffer(jsonBody))
	if err != nil {
		return nil, err
	}

	// 设置请求头（根据文档调整）
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-API-Key", APIKey)
	req.Header.Set("X-API-Secret", APISecret)

	// 发送请求
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	// 读取响应
	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	// 解析响应
	var response TTSResponse
	if err := json.Unmarshal(body, &response); err != nil {
		return nil, err
	}

	return &response, nil
}
