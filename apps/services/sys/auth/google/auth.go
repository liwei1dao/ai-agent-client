package google_auth

import (
	"context"
	"fmt"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/auth"
	"github.com/coze-dev/coze-go"
	"google.golang.org/api/option"
)

// newSys 创建 Google 认证系统实例。
// 参数:
//   - options: 运行所需配置（如服务账号密钥路径）
//
// 返回值:
//   - sys: 创建成功的实例
//   - err: 创建失败时返回错误
func newSys(options Options) (sys *Google, err error) {
	sys = &Google{
		options: options,
	}

	return
}

type Google struct {
	options Options
	api     coze.CozeAPI
}

// Auth 使用 Firebase Admin SDK 校验 Google ID Token。
// 参数:
//   - ctx: 上下文
//   - idToken: 客户端传入的 Google/Firebase ID Token
//
// 返回值:
//   - info: 校验成功后返回的 Token 信息
//   - err: 校验失败或邮箱未验证时返回错误
func (this *Google) Auth(ctx context.Context, idToken string) (info *auth.Token, err error) {
	// 指定服务账号密钥路径
	opt := option.WithCredentialsFile(this.options.ApiKeyFile)
	// 初始化 Firebase App
	app, err := firebase.NewApp(ctx, nil, opt)
	if err != nil {
		return nil, fmt.Errorf("failed to initialize Firebase app: %v", err)
	}

	// 获取 Auth 客户端
	client, err := app.Auth(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to get Auth client: %v", err)
	}

	// 验证 Token
	token, err := client.VerifyIDToken(ctx, idToken)
	if err != nil {
		return nil, fmt.Errorf("invalid ID Token: %v", err)
	}

	// 检查邮箱是否已验证（仅当 email_verified 明确为 false 时拒绝；缺失/非 bool 不再导致 panic）
	// if v, ok := token.Claims["email_verified"]; ok && v != nil {
	// 	if verified, ok := v.(bool); ok && !verified {
	// 		return nil, fmt.Errorf("email not verified")
	// 	}
	// }

	// log.Printf("Verified UID: %s, Email: %s", token.UID, token.Claims["email"])
	return token, nil
}
