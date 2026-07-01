package translate

import (
	"context"

	"github.com/volcengine/volcengine-go-sdk/service/translate20250301"
	"github.com/volcengine/volcengine-go-sdk/volcengine"
	"github.com/volcengine/volcengine-go-sdk/volcengine/credentials"
	"github.com/volcengine/volcengine-go-sdk/volcengine/session"
)

func newSys(options Options) (sys *TranslateSys, err error) {
	sys = &TranslateSys{
		options: options,
	}
	config := volcengine.NewConfig().
		WithRegion(options.Region).
		WithCredentials(credentials.NewStaticCredentials(options.AccessKey, options.SecretKey, ""))
	sys.session, err = session.NewSession(config)
	if err != nil {
		return
	}
	return
}

type TranslateSys struct {
	options Options
	session *session.Session
}

const maxCharsPerBatch = 5000
const maxTextsPerBatch = 128

func (this *TranslateSys) Translate(ctx context.Context, from string, to string, texts []string) (results []string, err error) {
	svc := translate20250301.New(this.session)
	results = make([]string, 0, len(texts))

	// 按字符数分批，每批不超过 maxCharsPerBatch
	batch := make([]string, 0)
	batchChars := 0
	for _, text := range texts {
		if (batchChars+len([]rune(text)) > maxCharsPerBatch || len(batch) >= maxTextsPerBatch) && len(batch) > 0 {
			var resp *translate20250301.TranslateTextOutput
			if resp, err = svc.TranslateText(&translate20250301.TranslateTextInput{
				SourceLanguage: volcengine.String(from),
				TargetLanguage: volcengine.String(to),
				TextList:       volcengine.StringSlice(batch),
			}); err != nil {
				return
			}
			for _, item := range resp.TranslationList {
				results = append(results, *item.Translation)
			}
			batch = batch[:0]
			batchChars = 0
		}
		batch = append(batch, text)
		batchChars += len([]rune(text))
	}

	// 发送剩余批次
	if len(batch) > 0 {
		var resp *translate20250301.TranslateTextOutput
		if resp, err = svc.TranslateText(&translate20250301.TranslateTextInput{
			SourceLanguage: volcengine.String(from),
			TargetLanguage: volcengine.String(to),
			TextList:       volcengine.StringSlice(batch),
		}); err != nil {
			return
		}
		for _, item := range resp.TranslationList {
			results = append(results, *item.Translation)
		}
	}
	return
}
