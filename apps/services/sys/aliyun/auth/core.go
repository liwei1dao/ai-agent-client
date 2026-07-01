package ali_auth

type (
	ISys interface {
		GetAppkey() string
		GetToken() (token string, err error)
	}

	TokenResult struct {
		ErrMsg string
		Token  struct {
			UserId     string
			Id         string
			ExpireTime int64
		}
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
func GetAppKey() string {
	return defsys.GetAppkey()
}
func GetToken() (token string, err error) {
	token, err = defsys.GetToken()
	return
}
