package gemini_test

import (
	"context"
	"fmt"
	"os"
	"testing"
	"yunyan/sys/google/gemini"
)

const (
	kGeminiModel = "gemini-2.5-flash"
)

// 注意：运行前通过 GEMINI_API_KEY 提供有效的 Gemini API Key
var (
	kGeminiApiKey = os.Getenv("GEMINI_API_KEY") // AIzaSy...
)

func newTestSys(t *testing.T) gemini.ISys {
	if kGeminiApiKey == "" {
		t.Skip("kGeminiApiKey is empty, skip")
	}
	sys, err := gemini.NewSys(
		gemini.SetApikey(kGeminiApiKey),
		gemini.SetModel(kGeminiModel),
	)
	if err != nil {
		t.Fatalf("NewSys err: %v", err)
	}
	return sys
}

func Test_Chat(t *testing.T) {
	sys := newTestSys(t)
	resp, err := sys.Chat(context.Background(), []gemini.Message{
		{Role: "system", Content: "你是一个简洁的中文助手。"},
		{Role: "user", Content: "用一句话介绍 Go 语言。"},
	})
	if err != nil {
		t.Fatalf("Chat err: %v", err)
	}
	fmt.Printf("resp: %s\n", resp.Content)
}

func Test_ChatStream(t *testing.T) {
	sys := newTestSys(t)
	ch := make(chan *gemini.ChatResponseChoice, 16)
	go func() {
		_ = sys.ChatForSteams(context.Background(), []gemini.Message{
			{Role: "user", Content: "从1数到5，每个数字占一行。"},
		}, ch)
	}()
	for c := range ch {
		fmt.Print(c.Content)
	}
	fmt.Println()
}

func Test_MissingKey(t *testing.T) {
	_, err := gemini.NewSys()
	if err == nil {
		t.Errorf("expect error when apikey missing, got nil")
	}
}

func Test_OnInit(t *testing.T) {
	if kGeminiApiKey == "" {
		t.Skip("kGeminiApiKey is empty, skip")
	}
	err := gemini.OnInit(map[string]interface{}{
		"Apikey": kGeminiApiKey,
		"Model":  kGeminiModel,
	})
	if err != nil {
		t.Fatalf("OnInit err: %v", err)
	}
	resp, err := gemini.Chat(context.Background(), []gemini.Message{
		{Role: "user", Content: "ping"},
	})
	if err != nil {
		t.Fatalf("Chat err: %v", err)
	}
	fmt.Printf("resp: %s\n", resp.Content)
}
