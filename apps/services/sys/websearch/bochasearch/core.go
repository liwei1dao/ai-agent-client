package bochasearch

import (
	"context"
)

type (
	// 根响应结构体
	BochaResponse struct {
		Code           int       `json:"code"`
		LogID          string    `json:"log_id"`
		ConversationID string    `json:"conversation_id"`
		Messages       []Message `json:"messages"`
	}

	// Message 消息结构体
	Message struct {
		Role        string `json:"role"`
		Type        string `json:"type"`
		ContentType string `json:"content_type"`
		Content     string `json:"content"` // 注意：根据实际内容可能需要进一步解析为具体结构体
	}
	ISys interface {
		Search(ctx context.Context, query, freshness string, count int) (results *BochaResponse, err error)
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

/*
- oneDay，一天内
- oneWeek，一周内
- oneMonth，一个月内
- oneYear，一年内
- noLimit，不限（默认）
- YYYY-MM-DD..YYYY-MM-DD，搜索日期范围，例如："2025-01-01..2025-04-06"
- YYYY-MM-DD，搜索指定日期，例如："2025-04-06"
*/
func Search(ctx context.Context, query, freshness string, count int) (results *BochaResponse, err error) {
	return defsys.Search(ctx, query, freshness, count)
}
