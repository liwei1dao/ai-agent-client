package translate

import "context"

type (
	ISys interface {
		Translate(ctx context.Context, from string, to string, text []string) (results []string, err error)
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

func Translate(ctx context.Context, from string, to string, text []string) (results []string, err error) {
	return defsys.Translate(ctx, from, to, text)
}
