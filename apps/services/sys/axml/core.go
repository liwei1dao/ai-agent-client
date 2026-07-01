package axml

type (
	ISys interface {
		Add(data string) (err error)
		Get(name string) (items []*XMLItem)
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

func Add(data string) error {
	return defsys.Add(data)
}

func Get(name string) (items []*XMLItem) {
	return defsys.Get(name)
}
