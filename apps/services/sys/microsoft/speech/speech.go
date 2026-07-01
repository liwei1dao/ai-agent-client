package speech

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// Azure Speech Batch Transcription v3.2
// Docs: https://learn.microsoft.com/en-us/azure/ai-services/speech-service/batch-transcription
const (
	apiPath = "/speechtotext/v3.2/transcriptions"
)

type Speech struct {
	options Options
	client  *http.Client
	baseURL string
}

func newSys(options Options) (sys *Speech, err error) {
	if options.Key == "" {
		return nil, fmt.Errorf("microsoft speech: key is required")
	}
	endpoint := strings.TrimRight(options.Endpoint, "/")
	if endpoint == "" {
		if options.Region == "" {
			return nil, fmt.Errorf("microsoft speech: endpoint or region is required")
		}
		endpoint = fmt.Sprintf("https://%s.api.cognitive.microsoft.com", options.Region)
	}
	sys = &Speech{
		options: options,
		client:  &http.Client{Timeout: 30 * time.Second},
		baseURL: endpoint,
	}
	return
}

// ==================== 创建任务 ====================

type createTaskRequest struct {
	DisplayName string                 `json:"displayName"`
	Locale      string                 `json:"locale"`
	ContentUrls []string               `json:"contentUrls"`
	Properties  createTaskProperties   `json:"properties"`
}

type createTaskProperties struct {
	DiarizationEnabled                    bool   `json:"diarizationEnabled"`
	WordLevelTimestampsEnabled            bool   `json:"wordLevelTimestampsEnabled"`
	DisplayFormWordLevelTimestampsEnabled bool   `json:"displayFormWordLevelTimestampsEnabled"`
	PunctuationMode                       string `json:"punctuationMode,omitempty"`
	ProfanityFilterMode                   string `json:"profanityFilterMode,omitempty"`
}

type createTaskResponse struct {
	Self    string `json:"self"`
	Status  string `json:"status"`
	Code    string `json:"code,omitempty"`
	Message string `json:"message,omitempty"`
}

func (this *Speech) CreateTask(audioURL, language string, enableSpeaker bool, callbackURL string) (taskID string, err error) {
	if audioURL == "" {
		return "", fmt.Errorf("audioURL is empty")
	}
	if language == "" {
		language = "en-US"
	}

	reqBody := createTaskRequest{
		DisplayName: "echomeet-" + time.Now().Format("20060102150405"),
		Locale:      language,
		ContentUrls: []string{audioURL},
		Properties: createTaskProperties{
			DiarizationEnabled:                    enableSpeaker,
			WordLevelTimestampsEnabled:            true,
			DisplayFormWordLevelTimestampsEnabled: true,
			PunctuationMode:                       "DictatedAndAutomatic",
			ProfanityFilterMode:                   "Masked",
		},
	}
	body, err := json.Marshal(reqBody)
	if err != nil {
		return "", fmt.Errorf("marshal request: %w", err)
	}

	req, err := http.NewRequest(http.MethodPost, this.baseURL+apiPath, bytes.NewReader(body))
	if err != nil {
		return "", fmt.Errorf("new request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Ocp-Apim-Subscription-Key", this.options.Key)

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
		return "", fmt.Errorf("azure speech create task failed: status=%d body=%s", resp.StatusCode, string(data))
	}

	var out createTaskResponse
	if err = json.Unmarshal(data, &out); err != nil {
		return "", fmt.Errorf("unmarshal response: %w body=%s", err, string(data))
	}
	// taskID 取自 self 末段 GUID
	taskID = extractTaskID(out.Self)
	if taskID == "" {
		return "", fmt.Errorf("missing taskID in response: %s", string(data))
	}
	return taskID, nil
}

func extractTaskID(self string) string {
	if self == "" {
		return ""
	}
	idx := strings.LastIndex(self, "/")
	if idx < 0 || idx == len(self)-1 {
		return ""
	}
	return self[idx+1:]
}

// ==================== 查询任务 ====================

type queryTaskResponse struct {
	Self   string `json:"self"`
	Status string `json:"status"` // NotStarted, Running, Succeeded, Failed
	Links  struct {
		Files string `json:"files"`
	} `json:"links"`
	Properties struct {
		Error struct {
			Code    string `json:"code"`
			Message string `json:"message"`
		} `json:"error"`
	} `json:"properties"`
}

type filesResponse struct {
	Values []fileValue `json:"values"`
}

type fileValue struct {
	Kind  string `json:"kind"` // Transcription | TranscriptionReport
	Name  string `json:"name"`
	Links struct {
		ContentUrl string `json:"contentUrl"`
	} `json:"links"`
}

// transcriptionResult Azure Speech 转写结果文件结构
type transcriptionResult struct {
	RecognizedPhrases []recognizedPhrase `json:"recognizedPhrases"`
}

type recognizedPhrase struct {
	RecognitionStatus string  `json:"recognitionStatus"`
	Speaker           int     `json:"speaker,omitempty"`
	Channel           int     `json:"channel"`
	OffsetInTicks     float64 `json:"offsetInTicks"`
	DurationInTicks   float64 `json:"durationInTicks"`
	NBest             []nBest `json:"nBest"`
}

type nBest struct {
	Confidence float64 `json:"confidence"`
	Display    string  `json:"display"`
	Lexical    string  `json:"lexical"`
}

func (this *Speech) QueryTask(taskID string) (status string, contexts []ContextStruct, err error) {
	reqURL := fmt.Sprintf("%s%s/%s", this.baseURL, apiPath, taskID)
	req, err := http.NewRequest(http.MethodGet, reqURL, nil)
	if err != nil {
		return StatusFailed, nil, fmt.Errorf("new request: %w", err)
	}
	req.Header.Set("Ocp-Apim-Subscription-Key", this.options.Key)

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
		return StatusFailed, nil, fmt.Errorf("azure speech query failed: status=%d body=%s", resp.StatusCode, string(data))
	}

	var out queryTaskResponse
	if err = json.Unmarshal(data, &out); err != nil {
		return StatusFailed, nil, fmt.Errorf("unmarshal response: %w body=%s", err, string(data))
	}

	switch out.Status {
	case "Succeeded":
		contexts, err = this.fetchTranscriptionResults(out.Links.Files)
		if err != nil {
			return StatusFailed, nil, err
		}
		return StatusSuccess, contexts, nil
	case "Failed":
		return StatusFailed, nil, fmt.Errorf("task failed: code=%s msg=%s", out.Properties.Error.Code, out.Properties.Error.Message)
	case "NotStarted", "Running":
		return StatusRunning, nil, nil
	default:
		return StatusFailed, nil, fmt.Errorf("unknown status: %s body=%s", out.Status, string(data))
	}
}

// fetchTranscriptionResults 通过 files 列表拉取 Transcription kind 的结果 JSON
func (this *Speech) fetchTranscriptionResults(filesURL string) (contexts []ContextStruct, err error) {
	if filesURL == "" {
		return nil, fmt.Errorf("files url is empty")
	}
	req, err := http.NewRequest(http.MethodGet, filesURL, nil)
	if err != nil {
		return nil, fmt.Errorf("new files request: %w", err)
	}
	req.Header.Set("Ocp-Apim-Subscription-Key", this.options.Key)

	resp, err := this.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("do files request: %w", err)
	}
	defer resp.Body.Close()

	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read files: %w", err)
	}
	if resp.StatusCode/100 != 2 {
		return nil, fmt.Errorf("list files failed: status=%d body=%s", resp.StatusCode, string(data))
	}

	var fl filesResponse
	if err = json.Unmarshal(data, &fl); err != nil {
		return nil, fmt.Errorf("unmarshal files: %w body=%s", err, string(data))
	}

	contexts = make([]ContextStruct, 0)
	for _, f := range fl.Values {
		if f.Kind != "Transcription" || f.Links.ContentUrl == "" {
			continue
		}
		// 下载结果文件
		resp2, err := this.client.Get(f.Links.ContentUrl)
		if err != nil {
			return nil, fmt.Errorf("download transcription: %w", err)
		}
		body, err := io.ReadAll(resp2.Body)
		resp2.Body.Close()
		if err != nil {
			return nil, fmt.Errorf("read transcription: %w", err)
		}
		var tr transcriptionResult
		if err = json.Unmarshal(body, &tr); err != nil {
			return nil, fmt.Errorf("unmarshal transcription: %w", err)
		}
		for _, p := range tr.RecognizedPhrases {
			if p.RecognitionStatus != "Success" || len(p.NBest) == 0 {
				continue
			}
			text := p.NBest[0].Display
			if text == "" {
				text = p.NBest[0].Lexical
			}
			// Azure 用 100ns Tick；转 ms：ticks / 10000
			startMs := int64(p.OffsetInTicks / 10000)
			endMs := startMs + int64(p.DurationInTicks/10000)
			speaker := ""
			if p.Speaker > 0 {
				speaker = fmt.Sprintf("%d", p.Speaker)
			}
			contexts = append(contexts, ContextStruct{
				Content:   text,
				StartTime: startMs,
				EndTime:   endMs,
				Speaker:   speaker,
			})
		}
	}
	return
}
