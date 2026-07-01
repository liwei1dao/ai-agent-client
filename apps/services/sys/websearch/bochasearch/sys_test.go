package bochasearch_test

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"testing"
	"yunyan/sys/websearch/bochasearch"
)

func Test_Handle(t *testing.T) {

	apiKey := os.Getenv("BOCHA_API_KEY")
	if apiKey == "" {
		t.Skip("BOCHA_API_KEY env not set")
	}
	endpoint := "https://api.bochaai.com/v1/web-search"

	// 请求参数
	requestBody, _ := json.Marshal(map[string]interface{}{
		"query":       "衡阳市和深圳市面积对比",
		"showSummary": true,
		"count":       1,
	})

	// 发起请求
	req, _ := http.NewRequestWithContext(context.Background(), "POST", endpoint, bytes.NewBuffer(requestBody))
	req.Header.Set("Authorization", "Bearer "+apiKey)
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		fmt.Println("Error:", err)
		return
	}
	defer resp.Body.Close()

	// 解析响应
	var response bochasearch.BochaResponse
	if err := json.NewDecoder(resp.Body).Decode(&response); err != nil {
		fmt.Println("Decode error:", err)
		return
	}
	fmt.Println("Response:", response)
}

func Test_Sys(t *testing.T) {
	apiKey := os.Getenv("BOCHA_API_KEY")
	if apiKey == "" {
		t.Skip("BOCHA_API_KEY env not set")
	}
	if err := bochasearch.OnInit(nil,
		bochasearch.SetApiKey(apiKey),
	); err != nil {
		return
	} else {
		results, err := bochasearch.Search(context.TODO(), "今日热点新闻", "noLimit", 3)
		fmt.Println(results, err)
	}
}
