package migu

import (
	"context"
	"encoding/json"
)

// 咪咕灵犀「智能体能力统一对外输出API」地址
const (
	// 灰度环境
	BaseURLGray = "https://app.c.vip.migu.cn/aiagent_terminal/chat/v1.0"
	// 正式环境
	BaseURLProd = "https://app.c.nf.migu.cn/aiagent_terminal/chat/v1.0"
)

// 咪咕响应 choices[0].delta.content 的类型
const (
	ContentTypeText     = "1" // 文本回复
	ContentTypeH5       = "2" // H5 卡片
	ContentTypeTemplate = "3" // 模板卡片
)

type (
	// ISys 咪咕灵犀上游聊天能力
	ISys interface {
		// Chat 以流式方式请求咪咕灵犀，解析后的 SSE 数据通过 ch 输出，结束时关闭 ch。
		Chat(ctx context.Context, req *Request, ch chan *StreamResp) (err error)
	}

	// Message 对话内容（与咪咕、OpenAI 的 role/content 结构一致）
	Message struct {
		Role    string `json:"role"`    // system / user / assistant
		Content string `json:"content"` // 问话
	}

	// Session 会话信息
	Session struct {
		SessionId  string `json:"sessionId,omitempty"`  // 三方 sessionId
		Attributes string `json:"attributes,omitempty"` // 三方自定义会话属性（json 字符串）
	}

	// Request 请求体，对应 PDF 的 body 参数
	Request struct {
		ReqId    string                 `json:"reqId"`             // 请求ID（必填）
		DeviceId string                 `json:"deviceId"`          // 设备ID（必填）
		Messages []Message              `json:"messages"`          // 对话内容（必填）
		Stream   bool                   `json:"stream"`            // 是否为流式，默认 true
		Session  *Session               `json:"session,omitempty"` // 会话信息
		History  []Message              `json:"history,omitempty"` // 历史对话
		Other    map[string]interface{} `json:"other,omitempty"`   // 其他额外参数
	}

	// Text 通用的 {"text": "..."} 结构
	Text struct {
		Text string `json:"text"`
	}

	// Content choices[0].delta.content，data 随 type 不同而不同，用 RawMessage 延迟解析
	// swaggertype 标签仅供 swag 文档生成识别（json.RawMessage 它无法解析），不影响运行时
	Content struct {
		Type string          `json:"type"`
		Data json.RawMessage `json:"data" swaggertype:"object"`
	}

	// Delta choices[0].delta，每次流式只会命中其中一种类型
	Delta struct {
		ReasoningContent *Text    `json:"reasoning_content,omitempty"` // 模型思考
		Content          *Content `json:"content,omitempty"`           // 文本/H5/模板
		RecommendPrompts []Text   `json:"recommendPrompts,omitempty"`  // 追问提示词
	}

	// Choice choices 元素
	Choice struct {
		Delta        Delta  `json:"delta"`
		FinishReason string `json:"finishReason,omitempty"` // fail:服务出错；filter:安全审核出错
	}

	// StreamResp 单条 SSE 数据（data: {...}）
	StreamResp struct {
		ReqId   string   `json:"reqId"`
		Model   string   `json:"model"`
		Session *Session `json:"session,omitempty"`
		Choices []Choice `json:"choices"`
	}

	// TextData 文本回复 / H5 卡片 / 模板卡片的 data 各自结构（按需取用）
	TextData struct {
		Text string `json:"text"`
	}
)

var defsys ISys

// OnInit 全局初始化入口，由服务 InitSys 调用
func OnInit(config map[string]interface{}, option ...Option) (err error) {
	defsys, err = newSys(newOptions(config, option...))
	return
}

// NewSys 创建独立实例
func NewSys(option ...Option) (sys ISys, err error) {
	sys, err = newSys(newOptionsByOption(option...))
	return
}

// Chat 包级调用入口
func Chat(ctx context.Context, req *Request, ch chan *StreamResp) (err error) {
	return defsys.Chat(ctx, req, ch)
}
