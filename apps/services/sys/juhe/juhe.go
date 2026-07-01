package juhe

func newSys(options *Options) (sys *JuHe, err error) {
	sys = &JuHe{options: options}
	return
}

// /聚合数据
type JuHe struct {
	options *Options
}
