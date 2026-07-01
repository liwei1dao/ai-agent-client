package bingsearch

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"time"
)

// newSys 创建 Bing 搜索系统对象
// 参数:
//   - options: 系统选项
//
// 返回值:
//   - sys: 系统对象指针
//   - err: 创建过程中的错误
//
// 异常:
//   - 无（最小实现，仅进行结构体初始化）
func newSys(options Options) (sys *BingSearch, err error) {
	sys = &BingSearch{
		options:    options,
		httpClient: &http.Client{Timeout: 30 * time.Second},
	}
	return
}

type BingSearch struct {
	options    Options
	httpClient *http.Client
}

// Search 执行网页搜索（最小实现）
// 参数:
//   - ctx: 上下文
//   - query: 搜索关键词
//   - count: 返回条数
//   - offset: 偏移量
//
// 返回值:
//   - results: BingResponse 最小结构
//   - err: 调用过程中的错误
//
// 异常:
//   - 当 API Key 未配置时返回错误
//   - 当网络请求失败、HTTP 状态非 200 或解析 JSON 失败时返回错误
func (this *BingSearch) Search(ctx context.Context, query string, count, offset int) (results *BingResponse, err error) {
	if this.options.ApiKey == "" {
		err = fmt.Errorf("bing api key is empty")
		return
	}
	endpoint := "https://api.bing.microsoft.com/v7.0/search"
	values := url.Values{}
	values.Set("q", query)
	if count > 0 {
		values.Set("count", fmt.Sprintf("%d", count))
	}
	if offset > 0 {
		values.Set("offset", fmt.Sprintf("%d", offset))
	}
	mkt := this.options.Market
	if mkt == "" {
		mkt = "zh-CN"
	}
	values.Set("mkt", mkt)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, fmt.Sprintf("%s?%s", endpoint, values.Encode()), nil)
	if err != nil {
		return
	}
	req.Header.Set("Ocp-Apim-Subscription-Key", this.options.ApiKey)
	resp, err := this.httpClient.Do(req)
	if err != nil {
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		err = fmt.Errorf("bing http status %d", resp.StatusCode)
		return
	}
	results = &BingResponse{}
	if err = json.NewDecoder(resp.Body).Decode(results); err != nil {
		return
	}
	return
}
