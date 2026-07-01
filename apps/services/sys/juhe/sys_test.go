package juhe_test

import (
	"fmt"
	"os"
	"testing"
	"yunyan/sys/juhe"
)

// 查询简单天气信息
func Test_sys_simpleWeather(t *testing.T) {
	apiKey := os.Getenv("JUHE_WEATHER_API_KEY")
	if apiKey == "" {
		t.Skip("JUHE_WEATHER_API_KEY not set, skip")
	}
	sys, _ := juhe.NewSys(juhe.SetSimpleWeather_ApiKey(apiKey))
	result, err := sys.SimpleWeather("上海")
	fmt.Printf("result:%v err:%v", result, err)
}

// 查询股票代码
func Test_sys_financebygid(t *testing.T) {
	apiKey := os.Getenv("JUHE_FINANCE_API_KEY")
	if apiKey == "" {
		t.Skip("JUHE_FINANCE_API_KEY not set, skip")
	}
	sys, _ := juhe.NewSys(juhe.SetFinance_ApiKey(apiKey))
	sys.Financebygid("sh601009")
}

// 查询股票代码
func Test_sys_financebytype(t *testing.T) {
	apiKey := os.Getenv("JUHE_FINANCE_API_KEY")
	if apiKey == "" {
		t.Skip("JUHE_FINANCE_API_KEY not set, skip")
	}
	sys, _ := juhe.NewSys(juhe.SetFinance_ApiKey(apiKey))
	sys.Financebytype("0")
}

// 查询头条新闻
func Test_sys_toutiao(t *testing.T) {
	apiKey := os.Getenv("JUHE_TOUTIAO_API_KEY")
	if apiKey == "" {
		t.Skip("JUHE_TOUTIAO_API_KEY not set, skip")
	}
	sys, _ := juhe.NewSys(juhe.SetToutiao_ApiKey(apiKey))
	sys.Toutiao("top")
}
