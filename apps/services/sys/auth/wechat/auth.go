package wechat_auth

import (
	"context"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net/http"

	"github.com/coze-dev/coze-go"
)

func newSys(options Options) (sys *WeChat, err error) {
	sys = &WeChat{
		options: options,
	}

	return
}

type WeChat struct {
	options Options
	api     coze.CozeAPI
}

func (this *WeChat) Auth(ctx context.Context, code string) (info *WeChatUserInfoResponse, err error) {
	// 调用微信 API 获取 Access Token
	url := fmt.Sprintf(
		"https://api.weixin.qq.com/sns/oauth2/access_token?appid=%s&secret=%s&code=%s&grant_type=authorization_code",
		this.options.AppID, this.options.AppSecret, code,
	)

	resp, err := http.Get(url)
	if err != nil {
		return nil, fmt.Errorf("failed to call WeChat API: %v", err)
	}
	defer resp.Body.Close()

	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response body: %v", err)
	}

	// 解析微信的响应
	var tokenResponse WeChatTokenResponse
	if err := json.Unmarshal(body, &tokenResponse); err != nil {
		return nil, fmt.Errorf("failed to parse WeChat response: %v", err)
	}

	// 检查微信错误码
	if tokenResponse.ErrCode != 0 {
		return nil, fmt.Errorf("微信错误: %d - %s", tokenResponse.ErrCode, tokenResponse.ErrMsg)
	}
	// 调用微信 API 获取用户信息
	url = fmt.Sprintf(
		"https://api.weixin.qq.com/sns/userinfo?access_token=%s&openid=%s",
		tokenResponse.AccessToken, tokenResponse.OpenID,
	)

	resp, err = http.Get(url)
	if err != nil {
		return nil, fmt.Errorf("failed to call WeChat API: %v", err)
	}
	defer resp.Body.Close()

	body, err = ioutil.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response body: %v", err)
	}

	// 解析微信的响应
	var userInfo WeChatUserInfoResponse
	if err := json.Unmarshal(body, &userInfo); err != nil {
		return nil, fmt.Errorf("failed to parse WeChat response: %v", err)
	}

	if userInfo.ErrCode != 0 {
		return nil, fmt.Errorf("微信错误: %d - %s", userInfo.ErrCode, userInfo.ErrMsg)
	}
	return &userInfo, nil
}
