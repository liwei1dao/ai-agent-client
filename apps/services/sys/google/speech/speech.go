package speech

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
)

// Google Cloud Speech-to-Text v1 LongRunningRecognize
// Docs: https://cloud.google.com/speech-to-text/docs/async-recognize
// 注意：长音频要求音频必须放在 GCS（gs://...），公网 http URL 不被该 API 接受

const (
	scope        = "https://www.googleapis.com/auth/cloud-platform"
	submitURL    = "https://speech.googleapis.com/v1/speech:longrunningrecognize"
	operationURL = "https://speech.googleapis.com/v1/operations/"
)

type Speech struct {
	options   Options
	client    *http.Client
	tokenSrc  oauth2.TokenSource
	projectId string
}

func newSys(options Options) (sys *Speech, err error) {
	data := options.JsonContent
	if len(data) == 0 {
		if options.JsonPath == "" {
			return nil, fmt.Errorf("google speech: JsonPath or JsonContent required")
		}
		data, err = os.ReadFile(options.JsonPath)
		if err != nil {
			return nil, fmt.Errorf("read service account: %w", err)
		}
	}
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

	cfg, err := google.JWTConfigFromJSON(data, scope)
	if err != nil {
		return nil, fmt.Errorf("jwt config: %w", err)
	}

	sys = &Speech{
		options:   options,
		client:    &http.Client{Timeout: time.Duration(options.Timeout) * time.Second},
		tokenSrc:  cfg.TokenSource(context.Background()),
		projectId: projectId,
	}
	return
}

// ==================== 创建任务 ====================

type recognitionConfig struct {
	Encoding                   string                  `json:"encoding,omitempty"`
	SampleRateHertz            int                     `json:"sampleRateHertz,omitempty"`
	LanguageCode               string                  `json:"languageCode"`
	EnableAutomaticPunctuation bool                    `json:"enableAutomaticPunctuation"`
	EnableWordTimeOffsets      bool                    `json:"enableWordTimeOffsets"`
	DiarizationConfig          *speakerDiarization     `json:"diarizationConfig,omitempty"`
}

type speakerDiarization struct {
	EnableSpeakerDiarization bool `json:"enableSpeakerDiarization"`
	MinSpeakerCount          int  `json:"minSpeakerCount,omitempty"`
	MaxSpeakerCount          int  `json:"maxSpeakerCount,omitempty"`
}

type recognitionAudio struct {
	Uri string `json:"uri"`
}

type longRunningRecognizeRequest struct {
	Config recognitionConfig `json:"config"`
	Audio  recognitionAudio  `json:"audio"`
}

type operationResponse struct {
	Name  string `json:"name"`
	Done  bool   `json:"done"`
	Error *struct {
		Code    int    `json:"code"`
		Message string `json:"message"`
	} `json:"error,omitempty"`
	Response *json.RawMessage `json:"response,omitempty"`
}

func (this *Speech) CreateTask(audioURL, language string, enableSpeaker bool, callbackURL string) (taskID string, err error) {
	if audioURL == "" {
		return "", fmt.Errorf("audioURL is empty")
	}
	if !strings.HasPrefix(audioURL, "gs://") {
		return "", fmt.Errorf("google speech requires gs:// URI, got: %s", audioURL)
	}
	if language == "" {
		language = "en-US"
	}

	cfg := recognitionConfig{
		Encoding:                   this.options.Encoding,
		SampleRateHertz:            this.options.SampleRateHertz,
		LanguageCode:               language,
		EnableAutomaticPunctuation: true,
		EnableWordTimeOffsets:      true,
	}
	if enableSpeaker {
		cfg.DiarizationConfig = &speakerDiarization{
			EnableSpeakerDiarization: true,
			MinSpeakerCount:          this.options.DiarizationMin,
			MaxSpeakerCount:          this.options.DiarizationMax,
		}
	}
	reqBody := longRunningRecognizeRequest{
		Config: cfg,
		Audio:  recognitionAudio{Uri: audioURL},
	}
	body, err := json.Marshal(reqBody)
	if err != nil {
		return "", fmt.Errorf("marshal request: %w", err)
	}

	token, err := this.tokenSrc.Token()
	if err != nil {
		return "", fmt.Errorf("get access token: %w", err)
	}

	req, err := http.NewRequest(http.MethodPost, submitURL, bytes.NewReader(body))
	if err != nil {
		return "", fmt.Errorf("new request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+token.AccessToken)

	resp, err := this.client.Do(req)
	if err != nil {
		return "", fmt.Errorf("do request: %w", err)
	}
	defer resp.Body.Close()

	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("read response: %w", err)
	}
	if resp.StatusCode/100 != 2 {
		return "", fmt.Errorf("google speech create task failed: status=%d body=%s", resp.StatusCode, string(data))
	}

	var out operationResponse
	if err = json.Unmarshal(data, &out); err != nil {
		return "", fmt.Errorf("unmarshal response: %w body=%s", err, string(data))
	}
	if out.Name == "" {
		return "", fmt.Errorf("missing operation name: body=%s", string(data))
	}
	return out.Name, nil
}

// ==================== 查询任务 ====================

// longRunningRecognizeResponse 异步识别结果
type longRunningRecognizeResponse struct {
	Type    string                  `json:"@type,omitempty"`
	Results []longRunningResultItem `json:"results"`
}

type longRunningResultItem struct {
	Alternatives []alternative `json:"alternatives"`
	ResultEndTime string       `json:"resultEndTime,omitempty"`
}

type alternative struct {
	Transcript string     `json:"transcript"`
	Confidence float64    `json:"confidence"`
	Words      []wordInfo `json:"words"`
}

type wordInfo struct {
	StartTime  string `json:"startTime"`  // 形如 "1.300s"
	EndTime    string `json:"endTime"`
	Word       string `json:"word"`
	SpeakerTag int    `json:"speakerTag,omitempty"`
}

func (this *Speech) QueryTask(taskID string) (status string, contexts []ContextStruct, err error) {
	if taskID == "" {
		return StatusFailed, nil, fmt.Errorf("taskID is empty")
	}
	token, err := this.tokenSrc.Token()
	if err != nil {
		return StatusFailed, nil, fmt.Errorf("get access token: %w", err)
	}

	// taskID 形如 projects/.../operations/{id} 或仅 {id}
	url := operationURL + strings.TrimPrefix(taskID, "operations/")
	if strings.HasPrefix(taskID, "projects/") || strings.HasPrefix(taskID, "operations/") {
		// Google 接受短名（"operations/{id}"）或仅 {id}；如返回了全路径用 v1/{name} 直接拼
		if strings.HasPrefix(taskID, "operations/") {
			url = "https://speech.googleapis.com/v1/" + taskID
		} else {
			// 长路径用 v1/{name} 形式
			url = "https://speech.googleapis.com/v1/" + taskID
		}
	}

	req, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		return StatusFailed, nil, fmt.Errorf("new request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+token.AccessToken)

	resp, err := this.client.Do(req)
	if err != nil {
		return StatusFailed, nil, fmt.Errorf("do request: %w", err)
	}
	defer resp.Body.Close()

	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return StatusFailed, nil, fmt.Errorf("read response: %w", err)
	}
	if resp.StatusCode/100 != 2 {
		return StatusFailed, nil, fmt.Errorf("google speech query failed: status=%d body=%s", resp.StatusCode, string(data))
	}

	var op operationResponse
	if err = json.Unmarshal(data, &op); err != nil {
		return StatusFailed, nil, fmt.Errorf("unmarshal operation: %w body=%s", err, string(data))
	}
	if op.Error != nil {
		return StatusFailed, nil, fmt.Errorf("operation error: code=%d msg=%s", op.Error.Code, op.Error.Message)
	}
	if !op.Done {
		return StatusRunning, nil, nil
	}
	if op.Response == nil {
		return StatusFailed, nil, fmt.Errorf("operation done but response missing: body=%s", string(data))
	}

	var lr longRunningRecognizeResponse
	if err = json.Unmarshal(*op.Response, &lr); err != nil {
		return StatusFailed, nil, fmt.Errorf("unmarshal response: %w body=%s", err, string(*op.Response))
	}
	contexts = extractContexts(lr)
	return StatusSuccess, contexts, nil
}

// extractContexts 把按 result/alternative 排布的词级时间戳合并成「整句」片段
// 策略：每个 result 取首选 alternative，按 speakerTag 切片；
// 若禁用说话人分离则整个 alternative 作为一句。
func extractContexts(lr longRunningRecognizeResponse) []ContextStruct {
	contexts := make([]ContextStruct, 0, len(lr.Results))
	for _, r := range lr.Results {
		if len(r.Alternatives) == 0 {
			continue
		}
		alt := r.Alternatives[0]
		if len(alt.Words) == 0 {
			// 无词级信息，作为单句
			if alt.Transcript != "" {
				contexts = append(contexts, ContextStruct{Content: alt.Transcript})
			}
			continue
		}
		// 按 speakerTag 切片
		var cur ContextStruct
		curSpeaker := -1
		var sb strings.Builder
		flush := func() {
			if sb.Len() > 0 {
				cur.Content = strings.TrimSpace(sb.String())
				contexts = append(contexts, cur)
				sb.Reset()
			}
		}
		for _, w := range alt.Words {
			startMs := parseDurationMs(w.StartTime)
			endMs := parseDurationMs(w.EndTime)
			if w.SpeakerTag != curSpeaker && sb.Len() > 0 {
				flush()
			}
			if sb.Len() == 0 {
				cur = ContextStruct{
					StartTime: startMs,
					Speaker:   speakerStr(w.SpeakerTag),
				}
				curSpeaker = w.SpeakerTag
			}
			if sb.Len() > 0 {
				sb.WriteByte(' ')
			}
			sb.WriteString(w.Word)
			cur.EndTime = endMs
		}
		flush()
	}
	return contexts
}

// parseDurationMs 解析 "1.300s" 形式为毫秒
func parseDurationMs(s string) int64 {
	if s == "" {
		return 0
	}
	s = strings.TrimSuffix(s, "s")
	v, err := strconv.ParseFloat(s, 64)
	if err != nil {
		return 0
	}
	return int64(v * 1000)
}

func speakerStr(tag int) string {
	if tag <= 0 {
		return ""
	}
	return strconv.Itoa(tag)
}
