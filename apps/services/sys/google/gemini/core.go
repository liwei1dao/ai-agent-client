package gemini

import "context"

type (
	// Message 与 sys/doubao 保持一致：role + content，方便模块层 provider 切换
	Message struct {
		Role    string `json:"role"`
		Content string `json:"content"`
	}

	// ChatResponseChoice 与 sys/doubao 保持一致
	ChatResponseChoice struct {
		Role    string                 `json:"role"`
		Content string                 `json:"content,omitempty"`
		Meta    map[string]interface{} `json:"meta,omitempty"`
	}

	ISys interface {
		Chat(ctx context.Context, msgs []Message) (result *ChatResponseChoice, err error)
		ChatForSteams(ctx context.Context, msgs []Message, choiceChan chan *ChatResponseChoice) (err error)
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

func Chat(ctx context.Context, msgs []Message) (result *ChatResponseChoice, err error) {
	return defsys.Chat(ctx, msgs)
}

func ChatForSteams(ctx context.Context, msgs []Message, choiceChan chan *ChatResponseChoice) (err error) {
	return defsys.ChatForSteams(ctx, msgs, choiceChan)
}
