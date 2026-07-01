package firebase_auth

import (
	"context"

	"firebase.google.com/go/v4/auth"
)

type (
	ISys interface {
		Auth(ctx context.Context, idToken string) (info *auth.Token, err error)
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

func Auth(ctx context.Context, idToken string) (info *auth.Token, err error) {
	return defsys.Auth(ctx, idToken)
}
