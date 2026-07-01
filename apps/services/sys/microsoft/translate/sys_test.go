package translate_test

import (
	"context"
	"fmt"
	"os"
	"strings"
	"testing"
	"yunyan/sys/microsoft/translate"
)

const (
	kAzureRegion   = "gobal"
	kAzureEndpoint = "https://api.cognitive.microsofttranslator.com"
)

// kAzureKey 从环境变量读取，缺失时对应用例跳过。
var kAzureKey = os.Getenv("AZURE_TRANSLATE_KEY")

// requireAzureKey 在需要真实 key 的用例前守卫。
func requireAzureKey(t *testing.T) {
	if kAzureKey == "" {
		t.Skip("AZURE_TRANSLATE_KEY env not set")
	}
}

// 单语种翻译：zh → en
func Test_Sys(t *testing.T) {
	requireAzureKey(t)
	sys, err := translate.NewSys(
		translate.SetKey(kAzureKey),
		translate.SetRegion(kAzureRegion),
		translate.SetEndpoint(kAzureEndpoint),
	)
	if err != nil {
		t.Fatalf("Sys Init err: %v", err)
	}
	results, err := sys.Translate(context.Background(), "zh", "en",
		[]string{"你好世界", "你好中国", "嗯"})
	if err != nil {
		t.Errorf("Translate err: %v", err)
		return
	}
	if len(results) != 3 {
		t.Errorf("expect 3 results, got %d: %v", len(results), results)
		return
	}
	fmt.Printf("zh→en results: %v\n", results)
}

// 欧洲小语种批量翻译（之前豆包报错的那几个）
func Test_EUSmallLangs(t *testing.T) {
	requireAzureKey(t)
	sys, err := translate.NewSys(
		translate.SetKey(kAzureKey),
		translate.SetRegion(kAzureRegion),
	)
	if err != nil {
		t.Fatalf("Sys Init err: %v", err)
	}
	texts := []string{"你好世界", "欢迎使用"}
	targets := []string{"hu", "bg", "hr", "sl", "sr", "lt", "lv", "et"}
	for _, to := range targets {
		results, err := sys.Translate(context.Background(), "zh", to, texts)
		if err != nil {
			t.Errorf("zh→%s fail: %v", to, err)
			continue
		}
		fmt.Printf("zh→%s: %v\n", to, results)
	}
}

// 源语言留空让 Azure 自动检测
func Test_AutoDetect(t *testing.T) {
	requireAzureKey(t)
	sys, err := translate.NewSys(
		translate.SetKey(kAzureKey),
		translate.SetRegion(kAzureRegion),
	)
	if err != nil {
		t.Fatalf("Sys Init err: %v", err)
	}
	results, err := sys.Translate(context.Background(), "", "zh",
		[]string{"Hello world", "Bonjour le monde"})
	if err != nil {
		t.Errorf("auto→zh err: %v", err)
		return
	}
	fmt.Printf("auto→zh: %v\n", results)
}

// 验证 OnInit + 包级 Translate 的完整初始化路径
func Test_OnInit(t *testing.T) {
	requireAzureKey(t)
	err := translate.OnInit(map[string]interface{}{
		"Key":      kAzureKey,
		"Region":   kAzureRegion,
		"Endpoint": kAzureEndpoint,
	})
	if err != nil {
		t.Fatalf("OnInit err: %v", err)
	}
	results, err := translate.Translate(context.Background(), "zh", "ja",
		[]string{"你好", "世界"})
	if err != nil {
		t.Errorf("Translate err: %v", err)
		return
	}
	fmt.Printf("zh→ja via package Translate: %v\n", results)
}

// Key 为空时应当直接报错（不进网络）
func Test_MissingKey(t *testing.T) {
	_, err := translate.NewSys(
		translate.SetRegion(kAzureRegion),
	)
	if err == nil {
		t.Errorf("expect error when Key missing, got nil")
	}
}

// 触发条数阈值分批：>1000 条短文本，应自动拆 2+ 批，结果数量与输入一致
func Test_BatchByCount(t *testing.T) {
	requireAzureKey(t)
	sys, err := translate.NewSys(
		translate.SetKey(kAzureKey),
		translate.SetRegion(kAzureRegion),
	)
	if err != nil {
		t.Fatalf("Sys Init err: %v", err)
	}
	const n = 1500
	texts := make([]string, 0, n)
	for i := 0; i < n; i++ {
		texts = append(texts, fmt.Sprintf("第%d条", i))
	}
	results, err := sys.Translate(context.Background(), "zh", "en", texts)
	if err != nil {
		t.Fatalf("Translate err: %v", err)
	}
	if len(results) != n {
		t.Errorf("expect %d results, got %d", n, len(results))
	}
	fmt.Printf("batch-by-count: in=%d out=%d, sample[0]=%q sample[last]=%q\n",
		n, len(results), results[0], results[len(results)-1])
}

// 触发字符阈值分批：每条 ~1000 字，50 条合计 ~50000 字，应至少拆 2 批
func Test_BatchByChars(t *testing.T) {
	requireAzureKey(t)
	sys, err := translate.NewSys(
		translate.SetKey(kAzureKey),
		translate.SetRegion(kAzureRegion),
	)
	if err != nil {
		t.Fatalf("Sys Init err: %v", err)
	}
	one := strings.Repeat("你好", 500) // 1000 字
	texts := make([]string, 0, 50)
	for i := 0; i < 50; i++ {
		texts = append(texts, one)
	}
	results, err := sys.Translate(context.Background(), "zh", "en", texts)
	if err != nil {
		t.Fatalf("Translate err: %v", err)
	}
	if len(results) != 50 {
		t.Errorf("expect 50 results, got %d", len(results))
	}
	fmt.Printf("batch-by-chars: in=50 out=%d, sample[0] head=%q\n",
		len(results), runeHead(results[0], 40))
}

func runeHead(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return string(r[:n]) + "..."
}
