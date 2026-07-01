package google

type (
	ISys interface {
		SpeechToken() (token string, err error)
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

func SpeechToken() (token string, err error) {
	return defsys.SpeechToken()
}
