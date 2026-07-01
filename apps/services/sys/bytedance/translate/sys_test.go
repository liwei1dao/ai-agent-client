package translate_test

import (
	"context"
	"fmt"
	"os"
	"testing"
	"yunyan/sys/bytedance/translate"

	"github.com/volcengine/volcengine-go-sdk/service/translate20250301"
	"github.com/volcengine/volcengine-go-sdk/volcengine"
	"github.com/volcengine/volcengine-go-sdk/volcengine/credentials"
	"github.com/volcengine/volcengine-go-sdk/volcengine/session"
)

var (
	kAccessKey      = os.Getenv("BYTEDANCE_ACCESS_KEY")
	kSecretKey      = os.Getenv("BYTEDANCE_SECRET_KEY")
	kServiceVersion = "2020-06-01"
)

func TestTranslateText(t *testing.T) {
	if kAccessKey == "" || kSecretKey == "" {
		t.Skip("BYTEDANCE_ACCESS_KEY / BYTEDANCE_SECRET_KEY env not set")
	}
	// 注意示例代码安全，代码泄漏会导致AK/SK泄漏，有极大的安全风险。
	ak, sk, region := kAccessKey, kSecretKey, "cn-beijing"
	config := volcengine.NewConfig().
		WithRegion(region).
		WithCredentials(credentials.NewStaticCredentials(ak, sk, ""))
	sess, err := session.NewSession(config)
	if err != nil {
		panic(err)
	}
	svc := translate20250301.New(sess)
	translateTextInput := &translate20250301.TranslateTextInput{
		SourceLanguage: volcengine.String("zh"),
		TargetLanguage: volcengine.String("en"),
		TextList:       []*string{volcengine.String("你好世界"), volcengine.String("你好中国"), volcengine.String("嗯")},
	}

	// 复制代码运行示例，请自行打印API返回值。
	resp, err := svc.TranslateText(translateTextInput)
	if err != nil {
		t.Errorf("TranslateText failed: %v", err)
		return
	}
	fmt.Printf("%v", resp)
}

func Test_Sys(t *testing.T) {
	if kAccessKey == "" || kSecretKey == "" {
		t.Skip("BYTEDANCE_ACCESS_KEY / BYTEDANCE_SECRET_KEY env not set")
	}
	if sys, err := translate.NewSys(
		translate.SetAccessKey(kAccessKey),
		translate.SetSecretKey(kSecretKey),
		translate.SetRegion("cn-beijing"),
	); err != nil {
		t.Errorf("Sys Init err:%v", err)
	} else {
		results, err := sys.Translate(context.Background(), "zh", "en", []string{"你好世界", "你好中国", "嗯"})
		fmt.Printf(" results:%v err:%v", results, err)
	}
}
