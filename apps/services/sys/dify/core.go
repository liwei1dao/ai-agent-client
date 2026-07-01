package dify

import "encoding/json"

const (
	baseurl      = "https://api.dify.ai/v1/chat-messages"
	workflowsurl = "https://api.dify.ai/v1/workflows/run"
)

type (
	ISys interface {
		ChatForChan(msg string, result chan string) (err error)
		Workflows(msg string, result chan string) (err error)
	}

	File struct {
		Type           string `json:"type"`
		TransferMethod string `json:"transfer_method"`
		URL            string `json:"url"`
	}

	ChatMessageRequest struct {
		Inputs         map[string]interface{} `json:"inputs"`
		Query          string                 `json:"query"`
		ResponseMode   string                 `json:"response_mode"`
		ConversationID string                 `json:"conversation_id"`
		User           string                 `json:"user"`
		Files          []File                 `json:"files"`
	}

	BaseEvent struct {
		Event          string `json:"event"`
		ConversationID string `json:"conversation_id"`
		MessageID      string `json:"message_id,omitempty"`
		CreatedAt      int64  `json:"created_at"`
		TaskID         string `json:"task_id,omitempty"` // 仅 TTS 相关事件存在
	}

	MessageEvent struct {
		BaseEvent
		Answer string `json:"answer"`
	}

	Usage struct {
		PromptTokens        int     `json:"prompt_tokens"`
		PromptUnitPrice     string  `json:"prompt_unit_price"`
		PromptPrice         string  `json:"prompt_price"`
		CompletionTokens    int     `json:"completion_tokens"`
		CompletionUnitPrice string  `json:"completion_unit_price"`
		CompletionPrice     string  `json:"completion_price"`
		TotalTokens         int     `json:"total_tokens"`
		TotalPrice          string  `json:"total_price"`
		Currency            string  `json:"currency"`
		Latency             float64 `json:"latency"`
	}

	RetrieverResource struct {
		Position     int     `json:"position"`
		DatasetID    string  `json:"dataset_id"`
		DatasetName  string  `json:"dataset_name"`
		DocumentID   string  `json:"document_id"`
		DocumentName string  `json:"document_name"`
		SegmentID    string  `json:"segment_id"`
		Score        float64 `json:"score"`
		Content      string  `json:"content"`
	}

	MessageEndEvent struct {
		BaseEvent
		ID       string `json:"id"`
		Metadata struct {
			Usage              Usage               `json:"usage"`
			RetrieverResources []RetrieverResource `json:"retriever_resources"`
		} `json:"metadata"`
	}

	TTSMessageEvent struct {
		BaseEvent
		Audio string `json:"audio"` // Base64 编码的音频数据
	}

	TTSMessageEndEvent struct {
		BaseEvent
		Audio string `json:"audio"` // 可能为空或包含最终音频
	}

	WorkflowResponse struct {
		TaskID        string `json:"task_id"`
		WorkflowRunID string `json:"workflow_run_id"`
		Data          struct {
			ID         string `json:"id"`
			WorkflowID string `json:"workflow_id"`
			Status     string `json:"status"`
			Outputs    struct {
				Text string `json:"text"`
			} `json:"outputs"`
			Error       interface{} `json:"error"` // 使用 interface{} 因为可能是 null 或其他类型
			ElapsedTime float64     `json:"elapsed_time"`
			TotalTokens int         `json:"total_tokens"`
			TotalSteps  int         `json:"total_steps"`
			CreatedAt   int64       `json:"created_at"`
			FinishedAt  int64       `json:"finished_at"`
		} `json:"data"`
	}

	// 通用事件结构
	EventData struct {
		Event  string          `json:"event"`
		TaskID string          `json:"task_id"`
		Data   json.RawMessage `json:"data"` // 这里使用 RawMessage 延迟解析
	}

	// workflow_started 事件结构
	WorkflowStartedData struct {
		WorkflowRunID string `json:"workflow_run_id"`
		ID            string `json:"id"`
		WorkflowID    string `json:"workflow_id"`
		SequenceNum   int    `json:"sequence_number"`
		CreatedAt     int64  `json:"created_at"`
	}

	// node_started 事件结构
	NodeStartedData struct {
		WorkflowRunID string                 `json:"workflow_run_id"`
		ID            string                 `json:"id"`
		NodeID        string                 `json:"node_id"`
		NodeType      string                 `json:"node_type"`
		Title         string                 `json:"title"`
		Index         int                    `json:"index"`
		Inputs        map[string]interface{} `json:"inputs"`
		CreatedAt     int64                  `json:"created_at"`
	}

	// node_finished 事件结构
	NodeFinishedData struct {
		WorkflowRunID string                 `json:"workflow_run_id"`
		ID            string                 `json:"id"`
		NodeID        string                 `json:"node_id"`
		NodeType      string                 `json:"node_type"`
		Title         string                 `json:"title"`
		Index         int                    `json:"index"`
		Inputs        map[string]interface{} `json:"inputs"`
		Outputs       map[string]interface{} `json:"outputs"`
		Status        string                 `json:"status"`
		ElapsedTime   float64                `json:"elapsed_time"`
		ExecutionMeta struct {
			TotalTokens int     `json:"total_tokens"`
			TotalPrice  float64 `json:"total_price"`
			Currency    string  `json:"currency"`
		} `json:"execution_metadata"`
		CreatedAt int64 `json:"created_at"`
	}

	// workflow_finished 事件结构
	WorkflowFinishedData struct {
		WorkflowRunID string                 `json:"workflow_run_id"`
		ID            string                 `json:"id"`
		WorkflowID    string                 `json:"workflow_id"`
		Outputs       map[string]interface{} `json:"outputs"`
		Status        string                 `json:"status"`
		ElapsedTime   float64                `json:"elapsed_time"`
		TotalTokens   int                    `json:"total_tokens"`
		TotalSteps    string                 `json:"total_steps"`
		CreatedAt     int64                  `json:"created_at"`
		FinishedAt    int64                  `json:"finished_at"`
	}

	// tts_message 事件结构
	TTSMessageData struct {
		ConversationID string `json:"conversation_id"`
		MessageID      string `json:"message_id"`
		CreatedAt      int64  `json:"created_at"`
		TaskID         string `json:"task_id"`
		Audio          string `json:"audio"`
	}
)

var defsys ISys

func OnInit(config map[string]interface{}, option ...Option) (err error) {
	defsys, err = newSys(newOptions(config, option...))
	return
}

func NewSys(option ...Option) (sys ISys, err error) {
	sys, err = newSys(newOptionsByOption(option...))
	return
}

func ChatForChan(message string, result chan string) (err error) {
	return defsys.ChatForChan(message, result)
}

func Workflows(msg string, result chan string) (err error) {
	return defsys.Workflows(msg, result)
}
