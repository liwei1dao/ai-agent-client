package qweather

import "time"

type (

	// WeatherLocationResponse 定义了API返回的天气位置响应数据结构体
	WeatherLocationResponse struct {
		Code     int            `json:"code"`     // 状态码
		Location []LocationData `json:"location"` // 地区/城市列表
		Refer    ReferData      `json:"refer"`    // 数据来源和许可信息
	}

	// LocationData 定义了地区/城市的数据结构体
	LocationData struct {
		Name      string `json:"name"`      // 地区/城市名称
		ID        string `json:"id"`        // 地区/城市ID
		Lat       string `json:"lat"`       // 地区/城市纬度
		Lon       string `json:"lon"`       // 地区/城市经度
		Adm2      string `json:"adm2"`      // 地区/城市的上级行政区划名称
		Adm1      string `json:"adm1"`      // 地区/城市所属一级行政区域
		Country   string `json:"country"`   // 地区/城市所属国家名称
		Tz        string `json:"tz"`        // 地区/城市所在时区
		UtcOffset string `json:"utcOffset"` // 地区/城市目前与UTC时间偏移的小时数
		IsDst     string `json:"isDst"`     // 地区/城市是否当前处于夏令时。1表示当前处于夏令时，0表示当前不是夏令时
		Type      string `json:"type"`      // 地区/城市的属性
		Rank      string `json:"rank"`      // 地区评分
		FxLink    string `json:"fxLink"`    // 该地区的天气预报网页链接
	}

	// WeatherResponse 定义了API返回的天气响应数据结构体
	WeatherResponse struct {
		Code       int       `json:"code"`       // 状态码
		UpdateTime time.Time `json:"updateTime"` // 当前API的最近更新时间
		FxLink     string    `json:"fxLink"`     // 当前数据的响应式页面链接
		Now        NowData   `json:"now"`        // 当前天气数据
		Refer      ReferData `json:"refer"`      // 数据来源和许可信息
	}

	// NowData 定义了当前天气数据结构体
	NowData struct {
		ObsTime   time.Time `json:"obsTime"`         // 数据观测时间
		Temp      string    `json:"temp"`            // 温度，默认单位：摄氏度
		FeelsLike string    `json:"feelsLike"`       // 体感温度，默认单位：摄氏度
		Icon      string    `json:"icon"`            // 天气状况的图标代码
		Text      string    `json:"text"`            // 天气状况的文字描述
		Wind360   string    `json:"wind360"`         // 风向360角度
		WindDir   string    `json:"windDir"`         // 风向
		WindScale string    `json:"windScale"`       // 风力等级
		WindSpeed string    `json:"windSpeed"`       // 风速，公里/小时
		Humidity  string    `json:"humidity"`        // 相对湿度，百分比数值
		Precip    string    `json:"precip"`          // 过去1小时降水量，默认单位：毫米
		Pressure  string    `json:"pressure"`        // 大气压强，默认单位：百帕
		Vis       string    `json:"vis"`             // 能见度，默认单位：公里
		Cloud     string    `json:"cloud,omitempty"` // 云量，百分比数值，可能为空
		Dew       string    `json:"dew,omitempty"`   // 露点温度，可能为空
	}

	// ReferData 定义了数据来源和许可信息结构体
	ReferData struct {
		Sources []string `json:"sources"` // 原始数据来源
		License []string `json:"license"` // 数据许可或版权声明
	}

	ISys interface {
		GeoApi(location string) (result *WeatherLocationResponse, err error)
		Weather(location string) (result *WeatherResponse, err error)
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

func GeoApi(location string) (result *WeatherLocationResponse, err error) {
	return defsys.GeoApi(location)
}

func Weather(location string) (result *WeatherResponse, err error) {
	return defsys.Weather(location)
}
