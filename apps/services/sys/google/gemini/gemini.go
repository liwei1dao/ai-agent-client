package gemini

import (
	"bufio"
	"bytes"
	"context"
	"yunyan/lego/sys/log"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// Gemini Native API
// Docs: https://ai.google.dev/gemini-api/docs

type Gemini struct {
	options Options
	client  *http.Client
}

func newSys(options Options) (sys *Gemini, err error) {
	if options.Apikey == "" {
		return nil, fmt.Errorf("google gemini: apikey is required")
	}
	sys = &Gemini{
		options: options,
		client:  &http.Client{Timeout: time.Duration(options.Timeout) * time.Second},
	}
	return
}

// ==================== 请求/响应结构 ====================

type genPart struct {
	Text string `json:"text"`
}

type genContent struct {
	Role  string    `json:"role,omitempty"`
	Parts []genPart `json:"parts"`
}

type genSystemInstruction struct {
	Parts []genPart `json:"parts"`
}

type generateContentRequest struct {
	Contents          []genContent          `json:"contents"`
	SystemInstruction *genSystemInstruction `json:"systemInstruction,omitempty"`
	GenerationConfig  *genGenerationConfig  `json:"generationConfig,omitempty"`
}

type genGenerationConfig struct {
	Temperature     float32 `json:"temperature,omitempty"`
	MaxOutputTokens int     `json:"maxOutputTokens,omitempty"`
}

type generateContentResponse struct {
	Candidates []struct {
		Content      genContent `json:"content"`
		FinishReason string     `json:"finishReason"`
	} `json:"candidates"`
	Error *struct {
		Code    int    `json:"code"`
		Message string `json:"message"`
		Status  string `json:"status"`
	} `json:"error,omitempty"`
}

// ==================== 实现 ====================

// buildRequest 将 OpenAI 风格的 messages 转为 Gemini 的 contents + systemInstruction
//   - role=system → systemInstruction
//   - role=user → contents[role=user]
//   - role=assistant/ai/model → contents[role=model]
func buildRequest(msgs []Message) *generateContentRequest {
	req := &generateContentRequest{
		Contents: make([]genContent, 0, len(msgs)),
	}
	var sysParts []genPart
	for _, m := range msgs {
		switch strings.ToLower(m.Role) {
		case "system":
			sysParts = append(sysParts, genPart{Text: m.Content})
		case "assistant", "ai", "model":
			req.Contents = append(req.Contents, genContent{
				Role:  "model",
				Parts: []genPart{{Text: m.Content}},
			})
		default: // user / 其他
			req.Contents = append(req.Contents, genContent{
				Role:  "user",
				Parts: []genPart{{Text: m.Content}},
			})
		}
	}
	if len(sysParts) > 0 {
		req.SystemInstruction = &genSystemInstruction{Parts: sysParts}
	}
	return req
}

func (this *Gemini) endpointFor(action string) string {
	return fmt.Sprintf("%s/v1beta/models/%s:%s?key=%s",
		strings.TrimRight(this.options.Endpoint, "/"),
		this.options.Model,
		action,
		this.options.Apikey,
	)
}

func (this *Gemini) Chat(ctx context.Context, msgs []Message) (result *ChatResponseChoice, err error) {
	stime := time.Now()
	reqBody := buildRequest(msgs)
	body, err := json.Marshal(reqBody)
	if err != nil {
		return nil, fmt.Errorf("marshal request: %w", err)
	}

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, this.endpointFor("generateContent"), bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("new request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")

	resp, err := this.client.Do(httpReq)
	if err != nil {
		this.options.Log.Errorf("gemini chat error: %v", err)
		return nil, err
	}
	defer resp.Body.Close()

	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response: %w", err)
	}
	if resp.StatusCode/100 != 2 {
		return nil, fmt.Errorf("gemini chat failed: status=%d body=%s", resp.StatusCode, string(data))
	}

	var out generateContentResponse
	if err = json.Unmarshal(data, &out); err != nil {
		return nil, fmt.Errorf("unmarshal response: %w body=%s", err, string(data))
	}
	if out.Error != nil {
		return nil, fmt.Errorf("gemini chat error: code=%d status=%s msg=%s", out.Error.Code, out.Error.Status, out.Error.Message)
	}
	if len(out.Candidates) == 0 {
		return nil, fmt.Errorf("gemini chat no candidates, body=%s", string(data))
	}
	var sb strings.Builder
	for _, p := range out.Candidates[0].Content.Parts {
		sb.WriteString(p.Text)
	}
	result = &ChatResponseChoice{
		Role:    "ai",
		Content: sb.String(),
	}
	this.options.Log.Debug("[统计]",
		log.Field{Key: "t", Value: time.Since(stime).Milliseconds()},
		log.Field{Key: "m", Value: "Chat"},
		log.Field{Key: "req", Value: msgs},
	)
	return
}

// ChatForSteams 使用 streamGenerateContent 流式接口，SSE 风格按行返回
func (this *Gemini) ChatForSteams(ctx context.Context, msgs []Message, choiceChan chan *ChatResponseChoice) (err error) {
	defer close(choiceChan)
	stime := time.Now()
	reqBody := buildRequest(msgs)
	body, err := json.Marshal(reqBody)
	if err != nil {
		return fmt.Errorf("marshal request: %w", err)
	}

	// alt=sse 让 Gemini 以 SSE 形式返回
	url := this.endpointFor("streamGenerateContent") + "&alt=sse"
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("new request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Accept", "text/event-stream")

	resp, err := this.client.Do(httpReq)
	if err != nil {
		this.options.Log.Errorf("gemini stream chat error: %v", err)
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode/100 != 2 {
		data, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("gemini stream failed: status=%d body=%s", resp.StatusCode, string(data))
	}

	reader := bufio.NewReader(resp.Body)
	for {
		line, e := reader.ReadString('\n')
		if e != nil && e != io.EOF {
			return fmt.Errorf("read stream: %w", e)
		}
		line = strings.TrimRight(line, "\r\n")
		if line == "" {
			if e == io.EOF {
				break
			}
			continue
		}
		// SSE 以 "data: " 开头
		const prefix = "data:"
		if !strings.HasPrefix(line, prefix) {
			if e == io.EOF {
				break
			}
			continue
		}
		payload := strings.TrimSpace(strings.TrimPrefix(line, prefix))
		if payload == "" || payload == "[DONE]" {
			if e == io.EOF {
				break
			}
			continue
		}
		var chunk generateContentResponse
		if jsErr := json.Unmarshal([]byte(payload), &chunk); jsErr != nil {
			// 一些情况下 Gemini 把 error 放外面，跳过解析失败的行
			continue
		}
		if chunk.Error != nil {
			return fmt.Errorf("gemini stream error: code=%d status=%s msg=%s",
				chunk.Error.Code, chunk.Error.Status, chunk.Error.Message)
		}
		if len(chunk.Candidates) == 0 {
			if e == io.EOF {
				break
			}
			continue
		}
		var sb strings.Builder
		for _, p := range chunk.Candidates[0].Content.Parts {
			sb.WriteString(p.Text)
		}
		if sb.Len() > 0 {
			choiceChan <- &ChatResponseChoice{
				Role:    "ai",
				Content: sb.String(),
			}
		}
		if e == io.EOF {
			break
		}
	}
	this.options.Log.Debug("[统计]",
		log.Field{Key: "t", Value: time.Since(stime).Milliseconds()},
		log.Field{Key: "m", Value: "ChatForSteams"},
	)
	return nil
}
