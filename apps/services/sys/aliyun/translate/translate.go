package translate

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/aliyun/alibaba-cloud-sdk-go/sdk"
	"github.com/aliyun/alibaba-cloud-sdk-go/sdk/auth/credentials"
	"github.com/aliyun/alibaba-cloud-sdk-go/sdk/requests"
)

// Aliyun Machine Translation (alimt) TranslateGeneral
// Docs: https://help.aliyun.com/document_detail/158244.html

type AliTranslate struct {
	options Options
	client  *sdk.Client
}

func newSys(options Options) (sys *AliTranslate, err error) {
	if options.AccessKeyId == "" || options.AccessKeySecret == "" {
		return nil, fmt.Errorf("aliyun translate: AccessKeyId/AccessKeySecret required")
	}
	cfg := sdk.NewConfig()
	cfg.HttpTransport = &http.Transport{IdleConnTimeout: 10 * time.Second}
	cfg.Timeout = 15 * time.Second
	cred := credentials.NewAccessKeyCredential(options.AccessKeyId, options.AccessKeySecret)
	cli, err := sdk.NewClientWithOptions(options.Region, cfg, cred)
	if err != nil {
		return nil, fmt.Errorf("new sdk client: %w", err)
	}
	sys = &AliTranslate{
		options: options,
		client:  cli,
	}
	return
}

// translateGeneralResponse Aliyun MT TranslateGeneral 响应
type translateGeneralResponse struct {
	RequestId string `json:"RequestId"`
	Code      string `json:"Code"`
	Message   string `json:"Message,omitempty"`
	Data      struct {
		WordCount  string `json:"WordCount"`
		Translated string `json:"Translated"`
	} `json:"Data"`
}

func (this *AliTranslate) translateOne(from, to, text string) (string, error) {
	req := requests.NewCommonRequest()
	req.Method = "POST"
	req.Scheme = "https"
	req.Domain = fmt.Sprintf("mt.%s.aliyuncs.com", this.options.Region)
	req.ApiName = "TranslateGeneral"
	req.Version = "2018-10-12"
	req.QueryParams["FormatType"] = this.options.FormatType
	req.QueryParams["SourceLanguage"] = from
	req.QueryParams["TargetLanguage"] = to
	req.QueryParams["SourceText"] = text
	req.QueryParams["Scene"] = this.options.Scene

	resp, err := this.client.ProcessCommonRequest(req)
	if err != nil {
		return "", fmt.Errorf("translate request: %w", err)
	}
	body := resp.GetHttpContentString()
	var out translateGeneralResponse
	if err = json.Unmarshal([]byte(body), &out); err != nil {
		return "", fmt.Errorf("unmarshal response: %w body=%s", err, body)
	}
	if out.Code != "" && out.Code != "200" {
		return "", fmt.Errorf("translate failed: code=%s msg=%s", out.Code, out.Message)
	}
	return out.Data.Translated, nil
}

// Translate 批量翻译，按 Concurrency 并发执行 TranslateGeneral
// from / to 为阿里 MT 语言码：zh / en / ja / ko / ...（保持调用方传入的标准）
func (this *AliTranslate) Translate(ctx context.Context, from, to string, texts []string) (results []string, err error) {
	if len(texts) == 0 {
		return []string{}, nil
	}
	results = make([]string, len(texts))
	errs := make([]error, len(texts))

	sem := make(chan struct{}, this.options.Concurrency)
	var wg sync.WaitGroup
	for i, t := range texts {
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		default:
		}
		wg.Add(1)
		sem <- struct{}{}
		go func(idx int, text string) {
			defer wg.Done()
			defer func() { <-sem }()
			// 空串/纯空白直接返回原值，阿里 MT 对空文本会报 code=10004
			if strings.TrimSpace(text) == "" {
				results[idx] = text
				return
			}
			r, e := this.translateOne(from, to, text)
			results[idx] = r
			errs[idx] = e
		}(i, t)
	}
	wg.Wait()
	for i, e := range errs {
		if e != nil {
			return nil, fmt.Errorf("translate index=%d failed: %w", i, e)
		}
	}
	return
}
