package filetrans

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

const (
	submitURL = "https://dashscope.aliyuncs.com/api/v1/services/audio/asr/transcription"
	queryURL  = "https://dashscope.aliyuncs.com/api/v1/tasks/"
)

func newSys(options Options) (sys *FileTrans, err error) {
	sys = &FileTrans{
		options: options,
		client: &http.Client{
			Timeout: 30 * time.Second,
		},
	}
	return
}

type FileTrans struct {
	options Options
	client  *http.Client
}

// ==================== 提交任务 ====================

// submitRequest DashScope 提交转写任务请求体
type submitRequest struct {
	Model string             `json:"model"`
	Input submitRequestInput `json:"input"`
	Parameters submitRequestParams `json:"parameters"`
}

type submitRequestInput struct {
	FileURLs []string `json:"file_urls"`
}

type submitRequestParams struct {
	LanguageHints      []string `json:"language_hints,omitempty"`
	SpeakerCount       *int     `json:"speaker_count,omitempty"`
	DiarizationEnabled bool     `json:"diarization_enabled"`
	NotifyURL          string   `json:"notify_url,omitempty"`
}

// submitResponse DashScope 提交任务的响应
type submitResponse struct {
	RequestID string `json:"request_id"`
	Output    struct {
		TaskID    string `json:"task_id"`
		TaskStatus string `json:"task_status"`
	} `json:"output"`
	Code    string `json:"code"`
	Message string `json:"message"`
}

// ==================== 查询任务 ====================

// queryResponse DashScope 查询任务的响应
type queryResponse struct {
	RequestID string `json:"request_id"`
	Output    struct {
		TaskID      string `json:"task_id"`
		TaskStatus  string `json:"task_status"`
		Code        string `json:"code"`
		Message     string `json:"message"`
		TaskMetrics struct {
			Total     int `json:"TOTAL"`
			Succeeded int `json:"SUCCEEDED"`
			Failed    int `json:"FAILED"`
		} `json:"task_metrics"`
		Results []taskResult `json:"results"`
	} `json:"output"`
	Code    string `json:"code"`
	Message string `json:"message"`
}

type taskResult struct {
	FileURL          string `json:"file_url"`
	TranscriptionURL string `json:"transcription_url"`
	SubtaskStatus    string `json:"subtask_status"`
	FailureReason    string `json:"failure_reason,omitempty"`
}

// transcriptionResult 转写结果 JSON（从 transcription_url 获取）
type transcriptionResult struct {
	FileURL string `json:"file_url"`
	Properties struct {
		AudioFormat           string `json:"audio_format"`
		Channels              []int  `json:"channels"`
		OriginalSamplingRate  int    `json:"original_sampling_rate"`
		OriginalDurationInMs  int64  `json:"original_duration_in_milliseconds"`
	} `json:"properties"`
	Transcripts []transcript `json:"transcripts"`
}

type transcript struct {
	ChannelID int        `json:"channel_id"`
	Sentences []sentence `json:"sentences"`
}

type sentence struct {
	Text      string      `json:"text"`
	BeginTime int64       `json:"begin_time"`
	EndTime   int64       `json:"end_time"`
	SpeakerID any `json:"speaker_id,omitempty"` // 开启说话人分离时为数字，关闭时为字符串
}

// ==================== 实现 ====================

func (this *FileTrans) CreateTask(audioURL, language string, enableSpeaker bool, callbackURL string) (taskID string, err error) {
	params := submitRequestParams{
		DiarizationEnabled: enableSpeaker,
		NotifyURL:          callbackURL,
	}
	if language != "" {
		params.LanguageHints = []string{language}
	}

	reqBody := submitRequest{
		Model: "paraformer-v2",
		Input: submitRequestInput{
			FileURLs: []string{audioURL},
		},
		Parameters: params,
	}

	bodyBytes, err := json.Marshal(reqBody)
	if err != nil {
		return "", fmt.Errorf("marshal request: %w", err)
	}

	req, err := http.NewRequest("POST", submitURL, strings.NewReader(string(bodyBytes)))
	if err != nil {
		return "", fmt.Errorf("new request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+this.options.ApiKey)
	req.Header.Set("X-DashScope-Async", "enable")

	resp, err := this.client.Do(req)
	if err != nil {
		return "", fmt.Errorf("do request: %w", err)
	}
	defer resp.Body.Close()

	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("read response: %w", err)
	}

	var result submitResponse
	if err = json.Unmarshal(data, &result); err != nil {
		return "", fmt.Errorf("unmarshal response: %w", err)
	}

	if result.Code != "" {
		return "", fmt.Errorf("create task failed: code=%s, message=%s", result.Code, result.Message)
	}

	return result.Output.TaskID, nil
}

func (this *FileTrans) QueryTask(taskID string) (status string, contexts []ContextStruct, err error) {
	reqURL := queryURL + taskID
	req, err := http.NewRequest("GET", reqURL, nil)
	if err != nil {
		return StatusFailed, nil, fmt.Errorf("new request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+this.options.ApiKey)

	resp, err := this.client.Do(req)
	if err != nil {
		return StatusFailed, nil, fmt.Errorf("do request: %w", err)
	}
	defer resp.Body.Close()

	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return StatusFailed, nil, fmt.Errorf("read response: %w", err)
	}

	var result queryResponse
	if err = json.Unmarshal(data, &result); err != nil {
		return StatusFailed, nil, fmt.Errorf("unmarshal response: %w", err)
	}

	if result.Code != "" {
		return StatusFailed, nil, fmt.Errorf("query failed: code=%s, message=%s", result.Code, result.Message)
	}

	switch result.Output.TaskStatus {
	case "SUCCEEDED":
		contexts, err = this.fetchTranscriptionResults(result.Output.Results)
		if err != nil {
			return StatusFailed, nil, err
		}
		return StatusSuccess, contexts, nil
	case "FAILED":
		reason := result.Output.Message
		if reason == "" && len(result.Output.Results) > 0 {
			reason = result.Output.Results[0].FailureReason
		}
		if reason == "" {
			reason = result.Message
		}
		return StatusFailed, nil, fmt.Errorf("task failed: %s", reason)
	case "PENDING", "RUNNING":
		return StatusRunning, nil, nil
	default:
		// UNKNOWN / 任务已过期（DashScope 任务结果仅保留 24 小时）/ 其他未知状态
		return StatusFailed, nil, fmt.Errorf("task unavailable: task_status=%s output.code=%s output.message=%s top.code=%s top.message=%s raw=%s",
			result.Output.TaskStatus, result.Output.Code, result.Output.Message, result.Code, result.Message, string(data))
	}
}

// fetchTranscriptionResults 从 transcription_url 下载转写结果并解析
func (this *FileTrans) fetchTranscriptionResults(results []taskResult) (contexts []ContextStruct, err error) {
	contexts = make([]ContextStruct, 0)
	for _, r := range results {
		if r.SubtaskStatus != "SUCCEEDED" || r.TranscriptionURL == "" {
			continue
		}
		resp, err := this.client.Get(r.TranscriptionURL)
		if err != nil {
			return nil, fmt.Errorf("fetch transcription: %w", err)
		}
		data, err := io.ReadAll(resp.Body)
		resp.Body.Close()
		if err != nil {
			return nil, fmt.Errorf("read transcription: %w", err)
		}

		var tr transcriptionResult
		if err = json.Unmarshal(data, &tr); err != nil {
			return nil, fmt.Errorf("unmarshal transcription: %w", err)
		}

		for _, t := range tr.Transcripts {
			for _, s := range t.Sentences {
				contexts = append(contexts, ContextStruct{
					Content:   s.Text,
					StartTime: s.BeginTime,
					EndTime:   s.EndTime,
					Speaker:   fmt.Sprintf("%v", s.SpeakerID),
				})
			}
		}
	}
	return
}
