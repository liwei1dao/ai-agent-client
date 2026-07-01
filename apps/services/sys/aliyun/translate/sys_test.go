package translate_test

import (
	"context"
	"fmt"
	"os"
	"testing"
	"yunyan/sys/aliyun/translate"
)

// 运行前替换为有效的阿里云 RAM AK/SK，并确保账号开通"机器翻译通用版"
var (
	kAliAccessKeyId     = os.Getenv("ALIYUN_ACCESS_KEY_ID")
	kAliAccessKeySecret = os.Getenv("ALIYUN_ACCESS_KEY_SECRET")
)

func newTestSys(t *testing.T) translate.ISys {
	if kAliAccessKeyId == "" || kAliAccessKeySecret == "" {
		t.Skip("kAliAccessKeyId / kAliAccessKeySecret empty, skip")
	}
	sys, err := translate.NewSys(
		translate.SetAccessKeyId(kAliAccessKeyId),
		translate.SetAccessKeySecret(kAliAccessKeySecret),
	)
	if err != nil {
		t.Fatalf("NewSys err: %v", err)
	}
	return sys
}

func Test_Translate(t *testing.T) {
	sys := newTestSys(t)
	results, err := sys.Translate(context.Background(), "zh", "en", []string{"你好世界", "今天天气不错", "再见"})
	if err != nil {
		t.Fatalf("Translate err: %v", err)
	}
	if len(results) != 3 {
		t.Errorf("expect 3 results, got %d", len(results))
	}
	fmt.Printf("zh→en: %v\n", results)
}

func Test_MissingKey(t *testing.T) {
	_, err := translate.NewSys()
	if err == nil {
		t.Errorf("expect error when AK/SK missing, got nil")
	}
}

func Test_Empty(t *testing.T) {
	sys := newTestSys(t)
	results, err := sys.Translate(context.Background(), "zh", "en", []string{})
	if err != nil {
		t.Fatalf("Translate err: %v", err)
	}
	if len(results) != 0 {
		t.Errorf("expect 0 results, got %d", len(results))
	}
}

func Test_OnInit(t *testing.T) {
	if kAliAccessKeyId == "" {
		t.Skip("AK empty, skip")
	}
	err := translate.OnInit(map[string]interface{}{
		"AccessKeyId":     kAliAccessKeyId,
		"AccessKeySecret": kAliAccessKeySecret,
	})
	if err != nil {
		t.Fatalf("OnInit err: %v", err)
	}
	results, err := translate.Translate(context.Background(), "zh", "ja", []string{"你好"})
	if err != nil {
		t.Fatalf("Translate err: %v", err)
	}
	fmt.Printf("zh→ja: %v\n", results)
}
