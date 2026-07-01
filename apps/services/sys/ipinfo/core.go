package ipinfo

type (
	ISys interface {
		GetIPInfo(ip string) (info *IPData, err error)
		Close()
	}
	IPData struct {
		IP            string `json:"ip"`                       // ip 地址
		Country       string `json:"country,omitempty"`        // 国家名称（xdb 原文，可能为中文或英文）
		Province      string `json:"province,omitempty"`       // 省 / 州
		City          string `json:"city,omitempty"`           // 城市
		ISP           string `json:"isp,omitempty"`            // 运营商
		CountryCode   string `json:"country_code,omitempty"`   // ISO 3166-1 alpha-2 国家编码
		ContinentCode string `json:"continent_code,omitempty"` // 洲编码：AS/EU/NA/SA/AF/OC/AN
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

func GetIPInfo(ip string) (info *IPData, err error) {
	return defsys.GetIPInfo(ip)
}

func Close() {
	if defsys != nil {
		defsys.Close()
	}
}
