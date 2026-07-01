package hefengweather

type (

	// 根数据结构，对应完整的JSON响应
	CityLookupResponse struct {
		Code     string `json:"code"` // 状态码，如"200"表示成功
		Location []struct {
			Name      string `json:"name"`      // 地点名称，如"New York"
			ID        string `json:"id"`        // 地点唯一标识，如"1E98E"
			Lat       string `json:"lat"`       // 纬度，字符串格式存储原始数据
			Lon       string `json:"lon"`       // 经度，字符串格式存储原始数据
			Adm2      string `json:"adm2"`      // 二级行政区，如"New York"
			Adm1      string `json:"adm1"`      // 一级行政区，如"New York"（此处为美国州名）
			Country   string `json:"country"`   // 国家，如"United States"
			Tz        string `json:"tz"`        // 时区，如"America/New_York"
			UtcOffset string `json:"utcOffset"` // UTC偏移量，如"-04:00"
			IsDst     string `json:"isDst"`     // 是否为夏令时，"1"表示是
			Type      string `json:"type"`      // 类型，如"city"表示城市
			Rank      string `json:"rank"`      // 排序权重，数字字符串格式
			FxLink    string `json:"fxLink"`    // 天气查询链接
		} `json:"location"` // 地点数组
		Refer struct {
			Sources []string `json:"sources"` // 数据来源列表，如["QWeather"]
			License []string `json:"license"` // 授权信息列表，如["QWeather Developers License"]
		} `json:"refer"` // 来源信息
	}

	WeatherResponse struct {
		Code       string `json:"code"`       // 状态码
		UpdateTime string `json:"updateTime"` // 数据更新时间
		FxLink     string `json:"fxLink"`     // 天气查询链接
		Daily      []struct {
			FxDate         string `json:"fxDate"`         // 预报日期
			Sunrise        string `json:"sunrise"`        // 日出时间
			Sunset         string `json:"sunset"`         // 日落时间
			Moonrise       string `json:"moonrise"`       // 月出时间
			Moonset        string `json:"moonset"`        // 月落时间
			MoonPhase      string `json:"moonPhase"`      // 月相
			MoonPhaseIcon  string `json:"moonPhaseIcon"`  // 月相图标代码
			TempMax        string `json:"tempMax"`        // 最高温度
			TempMin        string `json:"tempMin"`        // 最低温度
			IconDay        string `json:"iconDay"`        // 白天天气图标代码
			TextDay        string `json:"textDay"`        // 白天天气描述
			IconNight      string `json:"iconNight"`      // 夜间天气图标代码
			TextNight      string `json:"textNight"`      // 夜间天气描述
			Wind360Day     string `json:"wind360Day"`     // 白天风向角度
			WindDirDay     string `json:"windDirDay"`     // 白天风向
			WindScaleDay   string `json:"windScaleDay"`   // 白天风力等级
			WindSpeedDay   string `json:"windSpeedDay"`   // 白天风速
			Wind360Night   string `json:"wind360Night"`   // 夜间风向角度
			WindDirNight   string `json:"windDirNight"`   // 夜间风向
			WindScaleNight string `json:"windScaleNight"` // 夜间风力等级
			WindSpeedNight string `json:"windSpeedNight"` // 夜间风速
			Humidity       string `json:"humidity"`       // 相对湿度
			Precip         string `json:"precip"`         // 降水量
			Pressure       string `json:"pressure"`       // 气压
			Vis            string `json:"vis"`            // 能见度
			Cloud          string `json:"cloud"`          // 云量
			UvIndex        string `json:"uvIndex"`        // 紫外线指数
		} `json:"daily"` // 多日天气列表
		Refer struct {
			Sources []string `json:"sources"` // 数据来源
			License []string `json:"license"` // 授权信息
		} `json:"refer"` // 数据来源信息
	}

	ISys interface {
		CityLookup(location string) (result *CityLookupResponse, err error)
		QueryWeather(location string) (result *WeatherResponse, err error)
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

func CityLookup(location string) (result *CityLookupResponse, err error) {
	return defsys.CityLookup(location)
}

func QueryWeather(location string) (result *WeatherResponse, err error) {
	return defsys.QueryWeather(location)
}
