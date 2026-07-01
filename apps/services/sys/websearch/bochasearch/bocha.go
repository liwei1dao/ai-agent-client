package bochasearch

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
)

func newSys(options Options) (sys *BraveSearch, err error) {
	sys = &BraveSearch{
		options: options,
	}

	if err != nil {
		return
	}
	return
}

type BraveSearch struct {
	options Options
}

// 搜索网页信息
func (this *BraveSearch) Search(ctx context.Context, query, freshness string, count int) (results *BochaResponse, err error) {
	endpoint := "https://api.bochaai.com/v1/ai-search"

	// 请求参数
	requestBody, _ := json.Marshal(map[string]interface{}{
		"query":     query,
		"freshness": "noLimit",
		"count":     count,
		"answer":    false,
		"stream":    false,
	})

	// 发起请求
	req, _ := http.NewRequestWithContext(ctx, "POST", endpoint, bytes.NewBuffer(requestBody))
	req.Header.Set("Authorization", "Bearer "+this.options.ApiKey)
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		this.options.Log.Errorln(err)
		return
	}
	defer resp.Body.Close()
	results = &BochaResponse{}
	// 解析响应
	if err = json.NewDecoder(resp.Body).Decode(&results); err != nil {
		this.options.Log.Errorln(err)
		return
	}
	return
}
