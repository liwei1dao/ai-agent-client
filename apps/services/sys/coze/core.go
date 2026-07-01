package coze

import "context"

type (
	Message struct {
		Role    string `json:"role"`
		Content string `json:"content"`
	}
	//回应流式切片
	ChatResponseChoice struct {
		Role    string                 `json:"role"`
		Content string                 `json:"content,omitempty"`
		Meta    map[string]interface{} `json:"meta,omitempty"`
	}
	// ToolResponseCard 通用卡片结构（不解析底层元素细节）
	CardContent struct {
		CardType         int            `json:"card_type"`
		TemplateURL      string         `json:"template_url"`
		TemplateID       int64          `json:"template_id"`
		ResponseForModel string         `json:"response_for_model"`
		ContentType      int            `json:"content_type"`
		Data             string         `json:"data"`         // 卡片结构JSON字符串
		Variables        map[string]any `json:"variables"`    // 变量数据
		InfoInCard       string         `json:"info_in_card"` // 备用数据
		ResponseType     string         `json:"response_type"`
		XProperties      map[string]any `json:"x_properties"`
	}
	CardContentData struct {
		Variables map[string]CardData `json:"variables"` //卡片数据
	}
	CardData struct {
		ID           string      `json:"ID"`
		Name         string      `json:"name"`
		DefaultValue interface{} `json:"defaultValue"`
	}
	ISys interface {
		ChatForSteams(ctx context.Context, uid string, customVariables map[string]string, messages []Message, choiceChan chan *ChatResponseChoice) (err error)
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

func ChatForSteams(ctx context.Context, uid string, customVariables map[string]string, messages []Message, choiceChan chan *ChatResponseChoice) (err error) {
	return defsys.ChatForSteams(ctx, uid, customVariables, messages, choiceChan)
}
