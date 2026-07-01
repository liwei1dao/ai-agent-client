package translate_test

import (
	"context"
	"fmt"
	"os"
	"testing"
	"yunyan/sys/google/translate"
)

// 运行前通过 GOOGLE_SA_JSON_PATH 指定本机的服务账号 JSON 文件路径
var (
	kGoogleSaJson = os.Getenv("GOOGLE_SA_JSON_PATH") // 例：/Users/.../smart-bluetooth-447104-2b269474bd72.json
)

func newTestSys(t *testing.T) translate.ISys {
	if kGoogleSaJson == "" {
		t.Skip("kGoogleSaJson is empty, skip")
	}
	sys, err := translate.NewSys(
		translate.SetJsonPath(kGoogleSaJson),
	)
	if err != nil {
		t.Fatalf("NewSys err: %v", err)
	}
	return sys
}

func Test_Translate(t *testing.T) {
	sys := newTestSys(t)
	results, err := sys.Translate(context.Background(), "zh", "en", []string{"你好世界", "今天天气不错"})
	if err != nil {
		t.Fatalf("Translate err: %v", err)
	}
	if len(results) != 2 {
		t.Errorf("expect 2 results, got %d", len(results))
	}
	fmt.Printf("zh→en: %v\n", results)
}

func Test_MissingKey(t *testing.T) {
	_, err := translate.NewSys()
	if err == nil {
		t.Errorf("expect error when JsonPath/JsonContent missing, got nil")
	}
}

func Test_Empty(t *testing.T) {
	sys := newTestSys(t)
	r, err := sys.Translate(context.Background(), "zh", "en", []string{})
	if err != nil {
		t.Fatalf("Translate err: %v", err)
	}
	if len(r) != 0 {
		t.Errorf("expect 0 results, got %d", len(r))
	}
}

func Test_AutoDetect(t *testing.T) {
	sys := newTestSys(t)
	results, err := sys.Translate(context.Background(), "", "zh", []string{"Hello world", "Bonjour le monde"})
	if err != nil {
		t.Fatalf("Translate err: %v", err)
	}
	fmt.Printf("auto→zh: %v\n", results)
}
