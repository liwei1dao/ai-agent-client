package openai

import (
	"context"
	"encoding/json"

	"github.com/sashabaranov/go-openai"
)

type (
	ChatReq struct {
		Role    string `json:"role"`
		Content string `json:"content"`
	}
	Parameters struct {
		Type       string              `json:"type"`
		Properties map[string]Property `json:"properties"`
		Required   []string            `json:"required"`
	}
	Property struct {
		Type        string `json:"type"`
		Description string `json:"description"`
		// Pattern     string        `json:"pattern"`
		// MaxLength   string        `json:"max_length"`
		// Examples    []interface{} `json:"examples"`
	}
	ChatResponse struct {
		Role    string                 `json:"role"`
		Content string                 `json:"content,omitempty"`
		Meta    map[string]interface{} `json:"meta,omitempty"`
	}
	//回应流式切片
	ChatResponseChoice struct {
		Role    string                 `json:"role"`
		Content string                 `json:"content,omitempty"`
		Meta    map[string]interface{} `json:"meta,omitempty"`
	}
	ITool interface {
		GetToolInfo() openai.Tool
		Execute(args json.RawMessage) (any, string, error)
	}
	ISys interface {
		RegisterTools(tool ITool)
		Chat(ctx context.Context, messages []ChatReq) (resp *ChatResponse, err error)
		ChatForSteams(ctx context.Context, messages []ChatReq, choiceChan chan *ChatResponseChoice) (err error)
		CreateChatCompletion(ctx context.Context, request openai.ChatCompletionRequest) (response openai.ChatCompletionResponse, err error)
		CreateChatCompletionStream(ctx context.Context, request openai.ChatCompletionRequest) (stream *openai.ChatCompletionStream, err error)
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

func RegisterTools(tool ITool) {
	defsys.RegisterTools(tool)
}

func Chat(ctx context.Context, messages []ChatReq) (resp *ChatResponse, err error) {
	return defsys.Chat(ctx, messages)
}

func ChatForSteams(ctx context.Context, messages []ChatReq, choiceChan chan *ChatResponseChoice) (err error) {
	return defsys.ChatForSteams(ctx, messages, choiceChan)
}

func CreateChatCompletion(ctx context.Context, request openai.ChatCompletionRequest) (response openai.ChatCompletionResponse, err error) {
	return defsys.CreateChatCompletion(ctx, request)
}

func CreateChatCompletionStream(ctx context.Context, request openai.ChatCompletionRequest) (stream *openai.ChatCompletionStream, err error) {
	return defsys.CreateChatCompletionStream(ctx, request)
}
