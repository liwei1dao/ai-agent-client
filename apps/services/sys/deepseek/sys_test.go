package deepseek_test

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"testing"
	"time"
	"yunyan/sys/deepseek"
)

const (
	deepseekAPIURL = "https://api.deepseek.com/v1/chat/completions"
)

type DeepSeekClient struct {
	apiKey     string
	httpClient *http.Client
}

func NewDeepSeekClient(apiKey string) *DeepSeekClient {
	return &DeepSeekClient{
		apiKey:     apiKey,
		httpClient: &http.Client{Timeout: 30 * time.Second},
	}
}

// 增强版请求结构（假设支持搜索参数）
type ChatRequest struct {
	Model        string        `json:"model"`         // 指定支持搜索的模型
	Messages     []Message     `json:"messages"`      // 对话历史
	SearchConfig *SearchConfig `json:"search_config"` // 搜索配置
	Temperature  float64       `json:"temperature,omitempty"`
}

type SearchConfig struct {
	Enable          bool `json:"enable"`            // 启用搜索
	SearchDepth     int  `json:"search_depth"`      // 搜索深度
	RealTimeSearch  bool `json:"real_time_search"`  // 实时搜索
	ResultMaxTokens int  `json:"result_max_tokens"` // 结果最大长度
}

type Message struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type ChatResponse struct {
	Choices []struct {
		Message      Message    `json:"message"`
		SearchResult []struct { // 假设返回包含搜索结果
			Title   string `json:"title"`
			Snippet string `json:"snippet"`
			URL     string `json:"url"`
		} `json:"search_results,omitempty"`
	} `json:"choices"`
}

func (c *DeepSeekClient) ChatWithSearch(ctx context.Context, req ChatRequest) (*ChatResponse, error) {
	reqBody, _ := json.Marshal(req)

	httpReq, _ := http.NewRequestWithContext(ctx, "POST", deepseekAPIURL, bytes.NewReader(reqBody))
	httpReq.Header.Set("Authorization", "Bearer "+c.apiKey)
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Accept", "application/json")

	resp, err := c.httpClient.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("API请求失败: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("API返回异常状态码: %d", resp.StatusCode)
	}

	var response ChatResponse
	if err := json.NewDecoder(resp.Body).Decode(&response); err != nil {
		return nil, fmt.Errorf("响应解析失败: %w", err)
	}

	return &response, nil
}

func Test_DeepSeek(t *testing.T) {
	apiKey := os.Getenv("DEEPSEEK_API_KEY")
	if apiKey == "" {
		t.Skip("DEEPSEEK_API_KEY env not set")
	}

	client := NewDeepSeekClient(apiKey)

	// 构造包含搜索功能的请求
	request := ChatRequest{
		Model: "deepseek-chat", // 假设支持搜索的模型名称
		Messages: []Message{
			{
				Role:    "user",
				Content: "深圳今天的天气如何?",
			},
		},
		SearchConfig: &SearchConfig{
			Enable:          true,
			SearchDepth:     3,
			RealTimeSearch:  true,
			ResultMaxTokens: 500,
		},
		Temperature: 0.5,
	}

	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	response, err := client.ChatWithSearch(ctx, request)
	if err != nil {
		fmt.Printf("AI回答错误：%v", err)
		return
	}

	// 处理响应
	if len(response.Choices) > 0 {
		choice := response.Choices[0]
		fmt.Println("AI回答：", choice.Message.Content)

		if len(choice.SearchResult) > 0 {
			fmt.Println("\n引用的搜索结果：")
			for _, result := range choice.SearchResult {
				fmt.Printf("标题: %s\n摘要: %s\n链接: %s\n\n",
					result.Title,
					ellipsis(result.Snippet, 100),
					result.URL)
			}
		}
	}
}

// 辅助函数：截断长文本
func ellipsis(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen] + "..."
}

func Test_Sys(t *testing.T) {
	apiKey := os.Getenv("DEEPSEEK_API_KEY")
	if apiKey == "" {
		t.Skip("DEEPSEEK_API_KEY env not set")
	}
	if sys, err := deepseek.NewSys(
		deepseek.SetAppkey(apiKey),
	); err != nil {
		fmt.Printf("Sys Init err:%v", err)
	} else {
		result, err := sys.Chat([]deepseek.Message{{
			Role:    "user",
			Content: "茅台今日股价分析需包含技术指标",
			Web:     true,
		}})
		fmt.Printf(" result:%v err:%v", result, err)
	}
}
