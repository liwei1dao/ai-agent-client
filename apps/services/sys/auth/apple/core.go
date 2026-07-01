package apple_auth

import (
	"context"
)

type (
	ISys interface {
		Auth(ctx context.Context, idToken string) (id string, err error)
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

func Auth(ctx context.Context, idToken string) (id string, err error) {
	return defsys.Auth(ctx, idToken)
}
