package wechat_auth

import (
	"context"
)

type (
	ISys interface {
		Auth(ctx context.Context, idToken string) (info *WeChatUserInfoResponse, err error)
	}
	WeChatTokenResponse struct {
		AccessToken  string `json:"access_token"`
		ExpiresIn    int    `json:"expires_in"`
		RefreshToken string `json:"refresh_token"`
		OpenID       string `json:"openid"`
		Scope        string `json:"scope"`
		WeChatError         // 内嵌错误结构
	}

	WeChatUserInfoResponse struct {
		OpenID     string `json:"openid"`
		Nickname   string `json:"nickname"`
		HeadImgURL string `json:"headimgurl"`
		UnionID    string `json:"unionid"`
		WeChatError
	}

	WeChatError struct {
		ErrCode int    `json:"errcode"`
		ErrMsg  string `json:"errmsg"`
	}
)

var defsys ISys

func OnInit(config map[string]interface{}, option ...Option) (err error) {
	defsys, err = newSys(newOptions(config, option...))
	return
}

func NewSys(option ...Option) (sys ISys, err error) {
	sys, err = newSys(newOptionsByOption(option...))
	return
}

func Auth(ctx context.Context, idToken string) (info *WeChatUserInfoResponse, err error) {
	return defsys.Auth(ctx, idToken)
}
