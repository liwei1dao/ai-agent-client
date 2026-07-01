package lghttp

import "context"

/*
系统描述:mgo数据库驱动系统
*/
type (
	ISys interface {
		RequestForJson(ctx context.Context, method string, url string, args, result interface{}) (err error)
	}
)

var (
	defsys ISys
)

func OnInit(config map[string]interface{}, option ...Option) (err error) {
	defsys, err = newSys(newOptions(config, option...))
	return
}

func NewSys(option ...Option) (sys ISys, err error) {
	sys, err = newSys(newOptionsByOption(option...))
	return
}

//请求http
func RequestForJson(ctx context.Context, method string, url string, args, result interface{}) (err error) {
	return defsys.RequestForJson(ctx, method, url, args, result)
}
