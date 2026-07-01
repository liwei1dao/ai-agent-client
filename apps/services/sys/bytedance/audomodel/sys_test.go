package audomodel_test

import (
	"context"
	"fmt"
	"os"
	"testing"
	"yunyan/sys/bytedance/audomodel"
	"yunyan/sys/bytedance/translate"
)

var (
	kAudioAppID     = os.Getenv("BYTEDANCE_AUDIO_APPID")
	kAudioToken     = os.Getenv("BYTEDANCE_AUDIO_TOKEN")
	kAudioAccessKey = os.Getenv("BYTEDANCE_ACCESS_KEY")
	kAudioSecretKey = os.Getenv("BYTEDANCE_SECRET_KEY")
)

func TestRecognizeFlashByURL(t *testing.T) {
	if kAudioAppID == "" || kAudioToken == "" {
		t.Skip("BYTEDANCE_AUDIO_APPID / BYTEDANCE_AUDIO_TOKEN env not set")
	}
	sys, err := audomodel.NewSys(
		audomodel.SetBaseUrl("https://openspeech.bytedance.com/api/v3/auc/bigmodel"),
		audomodel.SetAppID(kAudioAppID),
		audomodel.SetToken(kAudioToken),
		audomodel.SetResourceId("volc.bigasr.auc"),
		audomodel.SetModelName("bigmodel"),
		audomodel.SetModelVersion("400"),
	)
	if err != nil {
		t.Fatalf("初始化失败: %v", err)
	}
	statusCode, logID, contexts, err := sys.RecognizeFlash("liwei1da0", "https://deepsound-1253517901.cos.ap-guangzhou.myqcloud.com/User/2019585175758831616/ExternalAudio/2026/03/24/stCRmukfdIcs.mp3", false, "ja-JP")
	if err != nil {
		fmt.Printf("识别失败: %v (code=%s, logid=%s)\n", err, statusCode, logID)
		return
	}
	// for _, v := range contexts {
	// 	fmt.Printf("Context: %+v\n", v)
	// }
	fmt.Printf("识别成功: code=%s, logid=%s, body=%v\n", statusCode, logID, contexts)

	if sys, err := translate.NewSys(
		translate.SetAccessKey(kAudioAccessKey),
		translate.SetSecretKey(kAudioSecretKey),
		translate.SetRegion("cn-beijing"),
	); err != nil {
		t.Errorf("Sys Init err:%v", err)
	} else {
		tests := make([]string, 0, len(contexts))
		for _, item := range contexts {
			tests = append(tests, item.Content)
		}
		// 映射ASR语言到火山翻译SDK的标准语言代码
		formLang := mapASRLangToTranslateLang("ja-JP")
		tolLang := mapASRLangToTranslateLang("en-US")
		results, err := sys.Translate(context.Background(), formLang, tolLang, tests)
		fmt.Printf("翻译成功:  results=%v, err=%v\n", results, err)
	}
}

// 语言标识映射函数：将识别侧的标识转为火山翻译SDK的标准代码
func mapASRLangToTranslateLang(asrLang string) string {
	// 定义映射表
	langMap := map[string]string{
		"":       "zh", // 空值（中文/方言）→ 中文
		"en-US":  "en",
		"ja-JP":  "ja",
		"id-ID":  "id",
		"es-MX":  "es",
		"pt-BR":  "pt",
		"de-DE":  "de",
		"fr-FR":  "fr",
		"ko-KR":  "ko",
		"fil-PH": "fil",
		"ms-MY":  "ms",
		"th-TH":  "th",
		"ar-SA":  "ar",
	}
	// 查找映射，未匹配则默认返回中文
	if targetLang, ok := langMap[asrLang]; ok {
		return targetLang
	}
	return "zh"
}

func TestCreateTask(t *testing.T) {
	if kAudioAppID == "" || kAudioToken == "" {
		t.Skip("BYTEDANCE_AUDIO_APPID / BYTEDANCE_AUDIO_TOKEN env not set")
	}
	sys, err := audomodel.NewSys(
		audomodel.SetBaseUrl("https://openspeech.bytedance.com/api/v3/auc/bigmodel"),
		audomodel.SetAppID(kAudioAppID),
		audomodel.SetToken(kAudioToken),
		audomodel.SetResourceId("volc.bigasr.auc"),
		audomodel.SetModelName("bigmodel"),
		audomodel.SetModelVersion("400"),
	)
	if err != nil {
		t.Fatalf("初始化失败: %v", err)
	}
	taskID, logID, err := sys.CreateTask("2019585175758831616", "https://deepsound-1253517901.cos.ap-guangzhou.myqcloud.com/User/2019585175758831616/LocalAudio/2026/02/27/rLLkZPargyKZ.wav", false, "en-US", "https://zens.yunyanservice.xyz/api/home/echomeet_backcall", fmt.Sprintf("%d", 49))
	if err != nil {
		fmt.Printf("创建任务失败: %v (taskID=%s, logID=%s)", err, taskID, logID)
	}
	fmt.Printf("创建任务成功: taskID=%s, logID=%s", taskID, logID)
}

func TestQueryTask(t *testing.T) {
	if kAudioAppID == "" || kAudioToken == "" {
		t.Skip("BYTEDANCE_AUDIO_APPID / BYTEDANCE_AUDIO_TOKEN env not set")
	}
	sys, err := audomodel.NewSys(
		audomodel.SetBaseUrl("https://openspeech.bytedance.com/api/v3/auc/bigmodel"),
		audomodel.SetAppID(kAudioAppID),
		audomodel.SetToken(kAudioToken),
		audomodel.SetResourceId("volc.bigasr.auc"),
		audomodel.SetModelName("bigmodel"),
		audomodel.SetModelVersion("400"),
	)
	if err != nil {
		t.Fatalf("初始化失败: %v", err)
	}
	statusCode, contexts, err := sys.QueryTask("1c09487e-9e92-4c4d-ba62-a442bacfc309", "2026041412232985B0813A5109F6939263")
	if err != nil {
		fmt.Printf("查询失败: %v (code=%s,)", err, statusCode)
	}
	fmt.Printf("查询成功: code=%s, logid=%v", statusCode, contexts)
}
