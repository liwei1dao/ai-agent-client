package facebook_auth

import (
	"context"
)

type (
	ISys interface {
		Auth(ctx context.Context, idToken string) (info *FacebookTokenInfo, err error)
	}
	FacebookTokenDebugResponse struct {
		Data *FacebookTokenInfo `json:"data"`
	}
	FacebookTokenInfo struct {
		AppID     string   `json:"app_id"`
		IsValid   bool     `json:"is_valid"`
		UserID    string   `json:"user_id"`
		ExpiresAt int64    `json:"expires_at"`
		Scopes    []string `json:"scopes"`
		Error     *struct {
			Code    int    `json:"code"`
			Message string `json:"message"`
		} `json:"error"`
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

func Auth(ctx context.Context, idToken string) (info *FacebookTokenInfo, err error) {
	return defsys.Auth(ctx, idToken)
}
