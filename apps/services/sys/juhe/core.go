package juhe

type (
	ISys interface {
		//简单天气查询
		SimpleWeather(city string) (result *WeatherResponse, err error)
		//股票查询 股票代码
		Financebygid(gid string) (result *StockResponse, err error)
		//股票查询 指数代码
		Financebytype(ftype string) (result *IndexResponse, err error)
		//新闻头条
		Toutiao(ntype string) (result *NewsResponse, err error)
	}
)

var (
	defsys ISys
)

func OnInit(config map[string]interface{}, opt ...Option) (err error) {
	var option *Options
	if option, err = newOptions(config, opt...); err != nil {
		return
	}
	defsys, err = newSys(option)
	return
}

func NewSys(opt ...Option) (sys ISys, err error) {
	var option *Options
	if option, err = newOptionsByOption(opt...); err != nil {
		return
	}
	sys, err = newSys(option)
	return
}

// 查询天气
func SimpleWeather(city string) (result *WeatherResponse, err error) {
	return defsys.SimpleWeather(city)
}

// 股票查询 股票代码
func Financebygid(gid string) (result *StockResponse, err error) {
	return defsys.Financebygid(gid)
}

// 股票查询 指数代码
func Financebytype(ftype string) (result *IndexResponse, err error) {
	return defsys.Financebytype(ftype)
}

// 股票查询 指数代码
func Toutiao(ftype string) (result *NewsResponse, err error) {
	return defsys.Toutiao(ftype)
}
