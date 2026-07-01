package bingsearch_test

import (
	"context"
	"yunyan/sys/websearch/bingsearch"
	"os"
	"testing"
)

// Test_BingSearch_NewSys 使用独立系统对象执行最小网页搜索
// 参数:
//   - t: Go 测试对象
//
// 返回值:
//   - 无返回值。测试过程中使用 t.Log 输出信息
//
// 异常:
//   - 当环境变量未配置时跳过测试
//   - 当搜索过程中出现错误时，测试失败
func Test_BingSearch_NewSys(t *testing.T) {
	apiKey := os.Getenv("BING_SEARCH_KEY")
	if apiKey == "" {
		t.Skip("跳过测试：未设置环境变量 BING_SEARCH_KEY")
	}
	sys, err := bingsearch.NewSys(
		bingsearch.SetApiKey(apiKey),
		bingsearch.SetMarket("zh-CN"),
	)
	if err != nil {
		t.Fatalf("初始化失败: %v", err)
	}
	res, err := sys.Search(context.Background(), "今日热点新闻", 3, 0)
	if err != nil {
		t.Fatalf("搜索失败: %v", err)
	}
	for i, v := range res.WebPages.Value {
		t.Logf("%d. %s - %s", i+1, v.Name, v.URL)
	}
}

// Test_BingSearch_OnInit 使用全局系统对象执行最小网页搜索
// 参数:
//   - t: Go 测试对象
//
// 返回值:
//   - 无返回值。测试过程中使用 t.Log 输出信息
//
// 异常:
//   - 当环境变量未配置时跳过测试
//   - 当搜索过程中出现错误时，测试失败
func Test_BingSearch_OnInit(t *testing.T) {
	apiKey := os.Getenv("BING_SEARCH_KEY")
	if apiKey == "" {
		t.Skip("跳过测试：未设置环境变量 BING_SEARCH_KEY")
	}
	if err := bingsearch.OnInit(nil,
		bingsearch.SetApiKey(apiKey),
		bingsearch.SetMarket("zh-CN"),
	); err != nil {
		t.Fatalf("OnInit 失败: %v", err)
	}
	res, err := bingsearch.Search(context.Background(), "OpenAI", 2, 0)
	if err != nil {
		t.Fatalf("搜索失败: %v", err)
	}
	for i, v := range res.WebPages.Value {
		t.Logf("%d. %s - %s", i+1, v.Name, v.URL)
	}
}
