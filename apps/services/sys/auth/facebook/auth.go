package facebook_auth

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io/ioutil"
	"net/http"
	"net/url"
	"time"

	"github.com/coze-dev/coze-go"
)

func newSys(options Options) (sys *Facebook, err error) {
	sys = &Facebook{
		options: options,
	}

	return
}

type Facebook struct {
	options Options
	api     coze.CozeAPI
}

// func (this *Facebook) Auth(ctx context.Context, accessToken string) (info *FacebookTokenInfo, err error) {
// // 调用 Facebook 的 Debug Token 接口
// url := fmt.Sprintf(
// 	"https://graph.facebook.com/debug_token?input_token=%s&access_token=%s|%s",
// 	accessToken, this.options.AppID, this.options.AppSecret,
// )

// resp, err := http.Get(url)
// if err != nil {
// 	return nil, fmt.Errorf("failed to call Facebook API: %v", err)
// }
// defer resp.Body.Close()

// body, err := ioutil.ReadAll(resp.Body)
// if err != nil {
// 	return nil, fmt.Errorf("failed to read response body: %v", err)
// }

// // 解析 Facebook 的响应
// var tokenResponse FacebookTokenDebugResponse
// if err := json.Unmarshal(body, &tokenResponse); err != nil {
// 	return nil, fmt.Errorf("failed to parse Facebook response: %v", err)
// }

// // 检查 Token 是否有效
// if !tokenResponse.Data.IsValid {
// 	return nil, fmt.Errorf("token is invalid")
// }

// // 检查 App ID 是否匹配
// if tokenResponse.Data.AppID != this.options.AppID {
// 	return nil, fmt.Errorf("invalid app ID")
// }

// // 返回用户 ID
// return tokenResponse.Data, nil
// }

func (f *Facebook) Auth(ctx context.Context, accessToken string) (*FacebookTokenInfo, error) {
	// 1. 创建带超时和重试的 HTTP 客户端
	client := &http.Client{
		Timeout: 10 * time.Second, // 避免无限等待
	}

	// 2. 编码 URL 参数，防止特殊字符问题
	encodedToken := url.QueryEscape(accessToken)
	url := fmt.Sprintf(
		"https://graph.facebook.com/debug_token?input_token=%s&access_token=%s|%s",
		encodedToken,
		url.QueryEscape(f.options.AppID),
		url.QueryEscape(f.options.AppSecret),
	)

	// 3. 添加上下文支持（如超时或取消）
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	// 4. 发送请求并处理响应
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("Facebook API request failed: %w", err)
	}
	defer resp.Body.Close()

	// 5. 检查 HTTP 状态码
	if resp.StatusCode != http.StatusOK {
		body, _ := ioutil.ReadAll(resp.Body)
		return nil, fmt.Errorf("Facebook API returned %d: %s", resp.StatusCode, string(body))
	}

	// 6. 解析响应体
	var tokenResponse FacebookTokenDebugResponse
	if err := json.NewDecoder(resp.Body).Decode(&tokenResponse); err != nil {
		return nil, fmt.Errorf("failed to decode Facebook response: %w", err)
	}

	// 7. 检查 Token 有效性及错误信息
	if tokenResponse.Data.Error != nil {
		return nil, fmt.Errorf("Facebook token error [%d]: %s",
			tokenResponse.Data.Error.Code,
			tokenResponse.Data.Error.Message)
	}

	if !tokenResponse.Data.IsValid {
		return nil, errors.New("token is invalid (no error details provided)")
	}

	// 8. 严格检查 AppID 类型（Facebook 返回的 AppID 可能是字符串或数字）
	if fmt.Sprintf("%v", tokenResponse.Data.AppID) != f.options.AppID {
		return nil, fmt.Errorf("app ID mismatch: expected %s, got %v",
			f.options.AppID, tokenResponse.Data.AppID)
	}

	return tokenResponse.Data, nil
}
