package bingsearch

import (
	"context"
)

type (
	// BingResponse 微软 Bing Web Search API 响应最小结构
	// 仅包含网页搜索的核心字段
	BingResponse struct {
		WebPages struct {
			Value []struct {
				Name    string `json:"name"`
				URL     string `json:"url"`
				Snippet string `json:"snippet"`
			} `json:"value"`
		} `json:"webPages"`
	} 
	// ISys 搜索系统接口
	// 只实现网页搜索的最小能力
	ISys interface {
		Search(ctx context.Context, query string, count, offset int) (results *BingResponse, err error)
	}
)

var defsys ISys

// OnInit 初始化全局系统对象
// 参数:
//   - config: 配置映射
//   - option: 可选项函数
//
// 返回值:
//   - err: 初始化过程中的错误
//
// 异常:
//   - 当内部对象创建失败时返回错误
func OnInit(config map[string]interface{}, option ...Option) (err error) {
	defsys, err = newSys(newOptions(config, option...))
	return
}

// NewSys 创建一个新的系统对象
// 参数:
//   - option: 可选项函数
//
// 返回值:
//   - sys: 系统对象
//   - err: 创建过程中的错误
//
// 异常:
//   - 当内部对象创建失败时返回错误
func NewSys(option ...Option) (sys ISys, err error) {
	sys, err = newSys(newOptionsByOption(option...))
	return
}

// Search 执行网页搜索
// 参数:
//   - ctx: 上下文
//   - query: 搜索关键词
//   - count: 返回条数
//   - offset: 偏移量
//
// 返回值:
//   - results: BingResponse 最小结构
//   - err: 调用过程中的错误
//
// 异常:
//   - 当请求失败或响应体解析失败时返回错误
func Search(ctx context.Context, query string, count, offset int) (results *BingResponse, err error) {
	return defsys.Search(ctx, query, count, offset)
}

