package translate

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"time"
)

// Azure Translator v3 /translate 官方硬限制:
//   - 单次请求总字符数 ≤ 50000(含所有 element, 多目标语言按倍数累加)
//   - 单次请求元素(element)个数 ≤ 1000
//   - URL 长度 ≤ 2048
// 预留 10% 余量, 避免边界 400
const (
	maxCharsPerBatch = 45000
	maxTextsPerBatch = 1000
)

type TranslateSys struct {
	options Options
	client  *http.Client
}

func newSys(options Options) (sys *TranslateSys, err error) {
	if options.Key == "" {
		return nil, fmt.Errorf("microsoft translate: key is required")
	}
	sys = &TranslateSys{
		options: options,
		client:  &http.Client{Timeout: 30 * time.Second},
	}
	return
}

type azureInput struct {
	Text string `json:"Text"`
}

type azureOutput struct {
	Translations []struct {
		Text string `json:"text"`
		To   string `json:"to"`
	} `json:"translations"`
}

func (this *TranslateSys) Translate(ctx context.Context, from string, to string, texts []string) (results []string, err error) {
	results = make([]string, 0, len(texts))
	batch := make([]string, 0, maxTextsPerBatch)
	batchChars := 0
	flush := func() error {
		if len(batch) == 0 {
			return nil
		}
		part, e := this.translateBatch(ctx, from, to, batch)
		if e != nil {
			return e
		}
		results = append(results, part...)
		batch = batch[:0]
		batchChars = 0
		return nil
	}
	for _, text := range texts {
		tl := len([]rune(text))
		// 单条超过单批总字符上限: 独立成批, 仍按一条发送
		// (Azure 单条上限同样是 50000, 超大单条的拒绝交给 API 反馈)
		if tl >= maxCharsPerBatch {
			if err = flush(); err != nil {
				return nil, err
			}
			part, e := this.translateBatch(ctx, from, to, []string{text})
			if e != nil {
				return nil, e
			}
			results = append(results, part...)
			continue
		}
		if (batchChars+tl > maxCharsPerBatch || len(batch) >= maxTextsPerBatch) && len(batch) > 0 {
			if err = flush(); err != nil {
				return nil, err
			}
		}
		batch = append(batch, text)
		batchChars += tl
	}
	if err = flush(); err != nil {
		return nil, err
	}
	return
}

func (this *TranslateSys) translateBatch(ctx context.Context, from, to string, texts []string) ([]string, error) {
	q := url.Values{}
	q.Set("api-version", "3.0")
	if from != "" && from != "auto" {
		q.Set("from", from)
	}
	q.Set("to", to)
	endpoint := this.options.Endpoint + "/translate?" + q.Encode()

	inputs := make([]azureInput, 0, len(texts))
	for _, t := range texts {
		inputs = append(inputs, azureInput{Text: t})
	}
	body, err := json.Marshal(inputs)
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Ocp-Apim-Subscription-Key", this.options.Key)
	if this.options.Region != "" {
		req.Header.Set("Ocp-Apim-Subscription-Region", this.options.Region)
	}
	resp, err := this.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("azure translate status=%d body=%s", resp.StatusCode, string(data))
	}
	var out []azureOutput
	if err := json.Unmarshal(data, &out); err != nil {
		return nil, fmt.Errorf("azure parse resp: %w body=%s", err, string(data))
	}
	results := make([]string, 0, len(out))
	for _, o := range out {
		if len(o.Translations) > 0 {
			results = append(results, o.Translations[0].Text)
		} else {
			results = append(results, "")
		}
	}
	return results, nil
}
