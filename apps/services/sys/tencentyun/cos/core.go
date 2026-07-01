package cos

import (
	"io"

	"github.com/tencentyun/cos-go-sdk-v5"
	sts "github.com/tencentyun/qcloud-cos-sts-sdk/go"
)

type (
	ISys interface {
		Sts() (result *sts.CredentialResult, err error)
		Get(name string) (resp *cos.Response, err error)
		Put(name string, r io.Reader) (publicURL string, err error)
		Delete(name string) (err error)
		GetFileUrl(name string) (publicURL string)
	}
)

var defsys ISys
var defopt Options

func OnInit(config map[string]interface{}, option ...Option) (err error) {
	defopt = newOptions(config, option...)
	defsys, err = newSys(defopt)
	return
}

func GetConfig() Options {
	return defopt
}

func NewSys(option ...Option) (sys ISys, err error) {
	sys, err = newSys(newOptionsByOption(option...))
	return
}

func Sts() (result *sts.CredentialResult, err error) {
	return defsys.Sts()
}

func Get(name string) (resp *cos.Response, err error) {
	return defsys.Get(name)
}
func Put(name string, r io.Reader) (publicURL string, err error) {
	return defsys.Put(name, r)
}

func Delete(name string) (err error) {
	return defsys.Delete(name)
}

func GetFileUrl(name string) (publicURL string) {
	return defsys.GetFileUrl(name)
}
