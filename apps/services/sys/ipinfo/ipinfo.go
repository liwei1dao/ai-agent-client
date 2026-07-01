package ipinfo

import (
	"fmt"
	"strings"

	"github.com/lionsoul2014/ip2region/binding/golang/service"
)

func newSys(opt *Options) (sys ISys, err error) {
	if opt.V4XdbPath == "" && opt.V6XdbPath == "" {
		err = fmt.Errorf("v4 and v6 xdb path are both empty")
		return
	}

	var policy int
	if policy, err = service.CachePolicyFromName(opt.CachePolicy); err != nil {
		return
	}

	var v4Cfg, v6Cfg *service.Config
	if opt.V4XdbPath != "" {
		if v4Cfg, err = service.NewV4Config(policy, opt.V4XdbPath, opt.Searchers); err != nil {
			err = fmt.Errorf("init v4 config: %w", err)
			return
		}
	}
	if opt.V6XdbPath != "" {
		if v6Cfg, err = service.NewV6Config(policy, opt.V6XdbPath, opt.Searchers); err != nil {
			err = fmt.Errorf("init v6 config: %w", err)
			return
		}
	}

	var ip2r *service.Ip2Region
	if ip2r, err = service.NewIp2Region(v4Cfg, v6Cfg); err != nil {
		err = fmt.Errorf("init ip2region: %w", err)
		return
	}

	return &IPInfo{opt: opt, ip2r: ip2r}, nil
}

type IPInfo struct {
	opt  *Options
	ip2r *service.Ip2Region
}

// GetIPInfo 查询 ip 的地理信息。xdb 返回格式为：国家|省|市|运营商|国家编码
func (this *IPInfo) GetIPInfo(ip string) (info *IPData, err error) {
	if ip == "" {
		err = fmt.Errorf("ip is empty")
		return
	}
	var region string
	if region, err = this.ip2r.Search(ip); err != nil {
		return
	}
	info = &IPData{IP: ip}
	if region == "" {
		return
	}
	parts := strings.Split(region, "|")
	get := func(i int) string {
		if i >= len(parts) {
			return ""
		}
		v := strings.TrimSpace(parts[i])
		if v == "0" {
			return ""
		}
		return v
	}
	info.Country = get(0)
	info.Province = get(1)
	info.City = get(2)
	info.ISP = get(3)
	info.CountryCode = strings.ToUpper(get(4))
	info.ContinentCode = continentOf(info.CountryCode)
	return
}

func (this *IPInfo) Close() {
	if this.ip2r != nil {
		this.ip2r.Close()
	}
}

// continentOf 根据 ISO 3166-1 alpha-2 国家编码返回对应的洲编码
// AS: 亚洲  EU: 欧洲  NA: 北美  SA: 南美  AF: 非洲  OC: 大洋洲  AN: 南极
func continentOf(cc string) string {
	if cc == "" {
		return ""
	}
	return countryToContinent[cc]
}

var countryToContinent = map[string]string{
	// 亚洲 AS
	"AF": "AS", "AM": "AS", "AZ": "AS", "BH": "AS", "BD": "AS", "BT": "AS",
	"BN": "AS", "KH": "AS", "CN": "AS", "CY": "AS", "GE": "AS", "HK": "AS",
	"IN": "AS", "ID": "AS", "IR": "AS", "IQ": "AS", "IL": "AS", "JP": "AS",
	"JO": "AS", "KZ": "AS", "KP": "AS", "KR": "AS", "KW": "AS", "KG": "AS",
	"LA": "AS", "LB": "AS", "MO": "AS", "MY": "AS", "MV": "AS", "MN": "AS",
	"MM": "AS", "NP": "AS", "OM": "AS", "PK": "AS", "PS": "AS", "PH": "AS",
	"QA": "AS", "SA": "AS", "SG": "AS", "LK": "AS", "SY": "AS", "TW": "AS",
	"TJ": "AS", "TH": "AS", "TL": "AS", "TR": "AS", "TM": "AS", "AE": "AS",
	"UZ": "AS", "VN": "AS", "YE": "AS",

	// 欧洲 EU
	"AL": "EU", "AD": "EU", "AT": "EU", "BY": "EU", "BE": "EU", "BA": "EU",
	"BG": "EU", "HR": "EU", "CZ": "EU", "DK": "EU", "EE": "EU", "FO": "EU",
	"FI": "EU", "FR": "EU", "DE": "EU", "GI": "EU", "GR": "EU", "GG": "EU",
	"HU": "EU", "IS": "EU", "IE": "EU", "IM": "EU", "IT": "EU", "JE": "EU",
	"XK": "EU", "LV": "EU", "LI": "EU", "LT": "EU", "LU": "EU", "MK": "EU",
	"MT": "EU", "MD": "EU", "MC": "EU", "ME": "EU", "NL": "EU", "NO": "EU",
	"PL": "EU", "PT": "EU", "RO": "EU", "RU": "EU", "SM": "EU", "RS": "EU",
	"SK": "EU", "SI": "EU", "ES": "EU", "SJ": "EU", "SE": "EU", "CH": "EU",
	"UA": "EU", "GB": "EU", "VA": "EU", "AX": "EU",

	// 北美洲 NA
	"AI": "NA", "AG": "NA", "AW": "NA", "BS": "NA", "BB": "NA", "BZ": "NA",
	"BM": "NA", "BQ": "NA", "VG": "NA", "CA": "NA", "KY": "NA", "CR": "NA",
	"CU": "NA", "CW": "NA", "DM": "NA", "DO": "NA", "SV": "NA", "GL": "NA",
	"GD": "NA", "GP": "NA", "GT": "NA", "HT": "NA", "HN": "NA", "JM": "NA",
	"MQ": "NA", "MX": "NA", "MS": "NA", "NI": "NA", "PA": "NA", "PR": "NA",
	"BL": "NA", "KN": "NA", "LC": "NA", "MF": "NA", "PM": "NA", "VC": "NA",
	"SX": "NA", "TT": "NA", "TC": "NA", "US": "NA", "VI": "NA",

	// 南美洲 SA
	"AR": "SA", "BO": "SA", "BR": "SA", "CL": "SA", "CO": "SA", "EC": "SA",
	"FK": "SA", "GF": "SA", "GY": "SA", "PY": "SA", "PE": "SA", "SR": "SA",
	"UY": "SA", "VE": "SA",

	// 非洲 AF
	"DZ": "AF", "AO": "AF", "BJ": "AF", "BW": "AF", "BF": "AF", "BI": "AF",
	"CV": "AF", "CM": "AF", "CF": "AF", "TD": "AF", "KM": "AF", "CG": "AF",
	"CD": "AF", "CI": "AF", "DJ": "AF", "EG": "AF", "GQ": "AF", "ER": "AF",
	"SZ": "AF", "ET": "AF", "GA": "AF", "GM": "AF", "GH": "AF", "GN": "AF",
	"GW": "AF", "KE": "AF", "LS": "AF", "LR": "AF", "LY": "AF", "MG": "AF",
	"MW": "AF", "ML": "AF", "MR": "AF", "MU": "AF", "YT": "AF", "MA": "AF",
	"MZ": "AF", "NA": "AF", "NE": "AF", "NG": "AF", "RE": "AF", "RW": "AF",
	"SH": "AF", "ST": "AF", "SN": "AF", "SC": "AF", "SL": "AF", "SO": "AF",
	"ZA": "AF", "SS": "AF", "SD": "AF", "TZ": "AF", "TG": "AF", "TN": "AF",
	"UG": "AF", "EH": "AF", "ZM": "AF", "ZW": "AF",

	// 大洋洲 OC
	"AS": "OC", "AU": "OC", "CK": "OC", "FJ": "OC", "PF": "OC", "GU": "OC",
	"KI": "OC", "MH": "OC", "FM": "OC", "NR": "OC", "NC": "OC", "NZ": "OC",
	"NU": "OC", "NF": "OC", "MP": "OC", "PW": "OC", "PG": "OC", "PN": "OC",
	"WS": "OC", "SB": "OC", "TK": "OC", "TO": "OC", "TV": "OC", "VU": "OC",
	"WF": "OC",

	// 南极洲 AN
	"AQ": "AN", "BV": "AN", "TF": "AN", "HM": "AN", "GS": "AN",
}
