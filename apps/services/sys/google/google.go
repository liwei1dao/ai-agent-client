package google

import (
	"context"
	"fmt"
	"log"
	"os"

	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
	"golang.org/x/oauth2/jwt"
	"google.golang.org/api/option"
	"google.golang.org/api/speech/v1"
)

func newSys(options Options) (sys *Google, err error) {
	sys = &Google{}
	// 读取服务账号密钥文件
	sys.jsonkey, err = os.ReadFile(options.JsonPath)
	if err != nil {
		log.Fatalf("Unable to read service account file: %v", err)
	}
	return
}

type Google struct {
	jsonkey []byte
}

// func (this *OAuth2) Token() (token *oauth2.Token, err error) {
// 	// 配置 OAuth 2.0 客户端
// 	ctx := context.Background()

// 	// 模拟用户授权：这通常在浏览器中完成，用户登录 Google 并授权
// 	authURL := this.config.AuthCodeURL("", oauth2.AccessTypeOffline)
// 	fmt.Println("Visit this URL for authorization:", authURL)
// 	// 通过授权码交换访问令牌（这里假设你已经获得了授权码）
// 	// 在实际场景中，您应该从用户那获取 `authCode`
// 	authCode := "YOUR_AUTH_CODE"
// 	token, err = this.config.Exchange(ctx, authCode)
// 	if err != nil {
// 		return nil, fmt.Errorf("failed to exchange auth code: %v", err)
// 	}
// 	return token, nil
// }

func (this *Google) Token() {
	// // 设置服务账号密钥文件路径
	// serviceAccountFile := "path/to/your/service-account-file.json"

	// // 读取服务账号密钥文件
	// data, err := os.ReadFile(serviceAccountFile)
	// if err != nil {
	// 	log.Fatalf("Unable to read service account file: %v", err)
	// }

	// // 使用服务账号密钥文件创建JWT配置
	// config, err := google.JWTConfigFromJSON(data, translate.CloudPlatformScope)
	// if err != nil {
	// 	log.Fatalf("Unable to parse service account file to config: %v", err)
	// }

	// // 创建HTTP客户端
	// client := config.Client(context.Background())

	// // 使用客户端创建翻译服务
	// translateService, err := translate.NewService(context.Background(), option.WithHTTPClient(client))
	// if err != nil {
	// 	log.Fatalf("Unable to create translate service: %v", err)
	// }

	// // 打印访问令牌
	// token, err := config.TokenSource(context.Background()).Token()
	// if err != nil {
	// 	log.Fatalf("Unable to retrieve token: %v", err)
	// }
	// fmt.Printf("Access Token: %s\n", token.AccessToken)
}

func (this *Google) SpeechToken() (tokenStr string, err error) {
	var (
		config *jwt.Config
		token  *oauth2.Token
	)
	// 使用服务账号密钥文件创建JWT配置
	config, err = google.JWTConfigFromJSON(this.jsonkey, speech.CloudPlatformScope)
	if err != nil {
		log.Fatalf("Unable to parse service account file to config: %v", err)
	}

	// 创建HTTP客户端
	client := config.Client(context.Background())

	// 使用客户端创建Speech-to-Text服务
	_, err = speech.NewService(context.Background(), option.WithHTTPClient(client))
	if err != nil {
		log.Fatalf("Unable to create speech service: %v", err)
	}

	// 打印访问令牌
	token, err = config.TokenSource(context.Background()).Token()
	if err != nil {
		log.Fatalf("Unable to retrieve token: %v", err)
	}
	fmt.Printf("Access Token: %s\n", token.AccessToken)
	tokenStr = token.AccessToken
	return
	// 使用speechService进行其他操作
	// 例如：调用speechService.Speech.Recognize()进行语音识别
}
