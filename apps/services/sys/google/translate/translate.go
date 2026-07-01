package translate

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"

	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
	"golang.org/x/oauth2/jwt"
)

// Google Cloud Translation v3
// Docs: https://cloud.google.com/translate/docs/reference/rest/v3/projects.locations/translateText

// 单次请求字符上限（v3 REST 单请求 30K 字符）。预留 10% 余量。
const (
	maxCharsPerBatch = 27000
	maxTextsPerBatch = 1024
	scope            = "https://www.googleapis.com/auth/cloud-translation"
)

type TranslateSys struct {
	options    Options
	client     *http.Client
	tokenSrc   oauth2.TokenSource
	projectId  string
}

func newSys(options Options) (sys *TranslateSys, err error) {
	data := options.JsonContent
	if len(data) == 0 {
		if options.JsonPath == "" {
			return nil, fmt.Errorf("google translate: JsonPath or JsonContent required")
		}
		data, err = os.ReadFile(options.JsonPath)
		if err != nil {
			return nil, fmt.Errorf("read service account: %w", err)
		}
	}

	// 解析出 project_id（如未显式配置）
	projectId := options.ProjectId
	if projectId == "" {
		var sa struct {
			ProjectId string `json:"project_id"`
		}
		if err = json.Unmarshal(data, &sa); err != nil {
			return nil, fmt.Errorf("parse service account: %w", err)
		}
		projectId = sa.ProjectId
	}
	if projectId == "" {
		return nil, fmt.Errorf("google translate: ProjectId is empty")
	}

	var cfg *jwt.Config
	cfg, err = google.JWTConfigFromJSON(data, scope)
	if err != nil {
		return nil, fmt.Errorf("jwt config: %w", err)
	}

	sys = &TranslateSys{
		options:   options,
		client:    &http.Client{Timeout: time.Duration(options.Timeout) * time.Second},
		tokenSrc:  cfg.TokenSource(context.Background()),
		projectId: projectId,
	}
	return
}

type translateTextRequest struct {
	SourceLanguageCode string   `json:"sourceLanguageCode,omitempty"`
	TargetLanguageCode string   `json:"targetLanguageCode"`
	Contents           []string `json:"contents"`
	MimeType           string   `json:"mimeType,omitempty"`
}

type translateTextResponse struct {
	Translations []struct {
		TranslatedText         string `json:"translatedText"`
		DetectedLanguageCode   string `json:"detectedLanguageCode,omitempty"`
	} `json:"translations"`
	Error *struct {
		Code    int    `json:"code"`
		Message string `json:"message"`
		Status  string `json:"status"`
	} `json:"error,omitempty"`
}

func (this *TranslateSys) endpoint() string {
	return fmt.Sprintf("https://translation.googleapis.com/v3/projects/%s/locations/%s:translateText",
		this.projectId, this.options.Location)
}

func (this *TranslateSys) Translate(ctx context.Context, from, to string, texts []string) (results []string, err error) {
	if len(texts) == 0 {
		return []string{}, nil
	}
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
	token, err := this.tokenSrc.Token()
	if err != nil {
		return nil, fmt.Errorf("get access token: %w", err)
	}

	body := translateTextRequest{
		SourceLanguageCode: from,
		TargetLanguageCode: to,
		Contents:           texts,
		MimeType:           "text/plain",
	}
	if from == "auto" {
		body.SourceLanguageCode = ""
	}
	data, err := json.Marshal(body)
	if err != nil {
		return nil, fmt.Errorf("marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, this.endpoint(), bytes.NewReader(data))
	if err != nil {
		return nil, fmt.Errorf("new request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+token.AccessToken)

	resp, err := this.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("do request: %w", err)
	}
	defer resp.Body.Close()

	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response: %w", err)
	}
	if resp.StatusCode/100 != 2 {
		return nil, fmt.Errorf("google translate failed: status=%d body=%s", resp.StatusCode, string(raw))
	}

	var out translateTextResponse
	if err = json.Unmarshal(raw, &out); err != nil {
		return nil, fmt.Errorf("unmarshal response: %w body=%s", err, string(raw))
	}
	if out.Error != nil {
		return nil, fmt.Errorf("google translate error: code=%d status=%s msg=%s", out.Error.Code, out.Error.Status, out.Error.Message)
	}
	results := make([]string, 0, len(out.Translations))
	for _, t := range out.Translations {
		results = append(results, t.TranslatedText)
	}
	if len(results) != len(texts) {
		return nil, fmt.Errorf("google translate length mismatch: in=%d out=%d", len(texts), len(results))
	}
	return results, nil
}
