package tavilysearch

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

// newSys 创建 Tavily 搜索系统对象
// 参数:
//   - options: 系统选项
//
// 返回值:
//   - sys: 系统对象指针
//   - err: 创建过程中的错误
//
// 异常:
//   - 无（最小实现，仅进行结构体初始化）
func newSys(options Options) (sys *TavilySearch, err error) {
	sys = &TavilySearch{
		options:    options,
		httpClient: &http.Client{Timeout: 30 * time.Second},
	}

	return
}

type TavilySearch struct {
	options    Options
	httpClient *http.Client
}

// Search 执行网页搜索（最小实现）
// 参数:
//   - ctx: 上下文
//   - query: 搜索关键词
//   - count: 返回条数
//   - offset: 偏移量（保留，不参与）
//
// 返回值:
//   - result: TavilyResponse 最小结构
//   - err: 调用过程中的错误
//
// 异常:
//   - 当 API Key 未配置、网络请求失败或解析失败时返回错误
func (this *TavilySearch) Search(ctx context.Context, query string, count, offset int) (result *TavilyResponse, err error) {
	if this.options.ApiKey == "" {
		err = fmt.Errorf("tavily api key is empty")
		return
	}
	apiURL := "https://api.tavily.com/search"

	// 创建请求体
	requestBody := map[string]interface{}{
		"query":        query,
		"max_results":  count,
		"search_depth": defaultDepth(this.options.SearchDepth),
	}

	// 序列化请求体
	jsonData, err := json.Marshal(requestBody)
	if err != nil {
		return
	}
	// 创建HTTP请求
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, apiURL, bytes.NewBuffer(jsonData))
	if err != nil {
		return
	}
	// 设置请求头
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+this.options.ApiKey)
	// 发送请求
	resp, err := this.httpClient.Do(req)
	if err != nil {
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		err = fmt.Errorf("tavily http status %d", resp.StatusCode)
		return
	}
	result = &TavilyResponse{}
	if err = json.NewDecoder(resp.Body).Decode(result); err != nil {
		return
	}

	return
}

func defaultDepth(v string) string {
	if v == "advanced" {
		return "advanced"
	}
	return "basic"
}
