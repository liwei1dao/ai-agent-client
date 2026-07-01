package amap

/*
高德 服务 系统
*/
type (
	IPath interface {
		GetPolylines() (polylines []string)
	}
	ISys interface {
		Coordinate(lng, lat string) (result *LocationResponse, err error)
		//搜索地址
		SearchPlace(keywords string, city string) (result *SearchPlaceResponse, err error)
		//地理/逆地理编码
		Geo(city, addr string) (result *GeocodeResponse, err error)
		//逆地理编码
		Geocode(location string) (result *ReverseGeocodeResponse, err error)
		//天气查询
		Weather(city, extensions string) (result *WeatherResponse, err error)
		//线路规划 驾车
		DirectionForDriving(origin, destination string) (result *RootResponse, err error)
		//线路规划 步行
		DirectionForWalking(origin, destination string) (result *RootResponse, err error)
		//线路规划 骑行
		DirectionForBicycling(origin, destination string) (result *RootResponse, err error)
		//线路规划 电动车
		DirectionForElectrobike(origin, destination string) (result *RootResponse, err error)
		//线路规划 公交
		DirectionForTsransit(origin, destination string, city1, city2 string) (result *TsransitResponse, err error)
		//周边搜索
		POISearch(location, radius, keywords string) (result *POIResponse, err error)
	}

	// 单一嵌套结构体，包含所有层级的字段
	SearchPlaceResponse struct {
		Status   string `json:"status"`   // 状态码
		Info     string `json:"info"`     // 状态信息
		Infocode string `json:"infocode"` // 信息码
		Count    string `json:"count"`    // 结果数量
		// 嵌套定义POI结构，无需单独声明结构体类型
		Pois []struct {
			Name     string `json:"name"`     // 名称
			Id       string `json:"id"`       // 唯一标识
			Location string `json:"location"` // 经纬度坐标（格式：经度,纬度）
			Type     string `json:"type"`     // 类型描述（如：科教文化服务;学校;高等院校）
			Typecode string `json:"typecode"` // 类型编码（如：141201）
			Pname    string `json:"pname"`    // 省份名称
			Cityname string `json:"cityname"` // 城市名称
			Adname   string `json:"adname"`   // 区县名称
			Address  string `json:"address"`  // 详细地址
			Pcode    string `json:"pcode"`    // 省份编码
			Citycode string `json:"citycode"` // 城市编码
			Adcode   string `json:"adcode"`   // 区县编码
			Distance string `json:"distance"` // 距离（可能为空字符串）
			Parent   string `json:"parent"`   // 父级POI ID（可能为空字符串）
		} `json:"pois"` // POI数组字段
	}

	LatLng struct {
		Lat float64
		Lng float64
	}
	LocationResponse struct {
		Status    string `json:"status"`    // 状态信息，如 "1"
		Info      string `json:"info"`      // 信息描述，如 "ok"
		Infocode  string `json:"infocode"`  // 信息代码，如 "10000"
		Locations string `json:"locations"` // 位置坐标，格式为 "经度1,纬度1;经度2,纬度2"
	}

	// 地理编码API响应根结构
	GeocodeResponse struct {
		Status   string        `json:"status"`   // 请求状态: "1"成功，"0"失败
		Info     string        `json:"info"`     // 状态说明，如："OK"
		Infocode string        `json:"infocode"` // 状态编码，如："10000" (成功码)
		Count    string        `json:"count"`    // 返回结果数量，如："1"
		Geocodes []GeocodeDara `json:"geocodes"` // 地理编码结果列表
	}

	// 单条地理编码结果
	GeocodeDara struct {
		FormattedAddress interface{}  `json:"formatted_address"` // 结构化地址，如："北京市"
		Country          string       `json:"country"`           // 国家名称，如："中国"
		Province         string       `json:"province"`          // 省份名称，如："北京市"
		Citycode         string       `json:"citycode"`          // 城市区号，如："010"
		City             interface{}  `json:"city"`              // 城市名称，如："北京市"
		District         interface{}  `json:"district"`          // 区县名称列表（通常为空）
		Township         []string     `json:"township"`          // 乡镇/街道列表（通常为空）
		Neighborhood     Neighborhood `json:"neighborhood"`      // 社区信息
		Building         Building     `json:"building"`          // 建筑物信息
		Adcode           string       `json:"adcode"`            // 区域编码，如："110000"
		Street           interface{}  `json:"street"`            // 街道信息列表（通常为空）
		Number           interface{}  `json:"number"`            // 门牌号列表（通常为空）
		Location         interface{}  `json:"location"`          // 经纬度坐标，如："116.407387,39.904179"
		Level            interface{}  `json:"level"`             // 地址匹配级别，如："省"
	}

	// 社区信息结构
	Neighborhood struct {
		Name []string `json:"name"` // 社区名称列表
		Type []string `json:"type"` // 社区类型列表
	}

	// 建筑物信息结构
	Building struct {
		Name []string `json:"name"` // 建筑物名称列表
		Type []string `json:"type"` // 建筑物类型列表
	}

	// ReverseGeocodeResponse 表示高德地图逆地理编码的返回结果
	ReverseGeocodeResponse struct {
		Status    string `json:"status"`   // 请求状态，"1" 表示成功
		Info      string `json:"info"`     // 信息描述，通常为 "OK"
		Infocode  string `json:"infocode"` // 信息代码，"10000" 表示成功
		Regeocode struct {
			FormattedAddress interface{} `json:"formatted_address"` // 完整地址，如 "北京市海淀区燕园街道北京大学"
			AddressComponent struct {
				City     interface{} `json:"city"`     // 城市（有时为 []）
				Province interface{} `json:"province"` // 省份，如 "北京市"
				Adcode   interface{} `json:"adcode"`   // 区域代码，如 "110108"
				District interface{} `json:"district"` // 区县名称，如 "海淀区"
				Towncode interface{} `json:"towncode"` // 镇/街道代码

				StreetNumber struct {
					Number    interface{} `json:"number"`    // 门牌号，如 "5号"
					Location  interface{} `json:"location"`  // 经纬度坐标，如 "116.310454,39.992734"
					Direction interface{} `json:"direction"` // 方向，如 "东北"
					Distance  interface{} `json:"distance"`  // 距离，如 "94.5489"
					Street    interface{} `json:"street"`    // 街道名称，如 "颐和园路"
				} `json:"streetNumber"`

				Country  interface{} `json:"country"`  // 国家名称，如 "中国"`
				Township interface{} `json:"township"` // 街道/乡镇名称，如 "燕园街道"`

				BusinessAreas interface{} `json:"businessAreas"`

				Building struct {
					Name interface{} `json:"name"` // 建筑名称，如 "北京大学"
					Type interface{} `json:"type"` // 建筑类别
				} `json:"building"`

				Neighborhood struct {
					Name interface{} `json:"name"` // 小区/社区名称，如 "北京大学"
					Type interface{} `json:"type"` // 类型说明
				} `json:"neighborhood"`

				Citycode string `json:"citycode"` // 城市代码，如 "010"
			} `json:"addressComponent"`
		} `json:"regeocode"`
	}

	// 高德天气API响应根结构
	WeatherResponse struct {
		Status    string        `json:"status"`   // 请求状态: "1"成功，"0"失败
		Count     string        `json:"count"`    // 返回数据条数，如："1"
		Info      string        `json:"info"`     // 状态说明，如："OK"
		Infocode  string        `json:"infocode"` // 状态编码，如："10000" (成功码)
		Lives     []WeatherData `json:"lives"`    // 实时天气数据列表
		Forecasts []struct {    // 预报列表
			City       string      `json:"city"`       // 城市名称，例如“东城区”
			Adcode     interface{} `json:"adcode"`     // 城市对应的行政区划编码
			Province   interface{} `json:"province"`   // 省份名称，例如“北京”
			Reporttime interface{} `json:"reporttime"` // 天气预报发布时间
			Casts      []struct {  // 每天的天气预报详情
				Date           string `json:"date"`            // 预报日期
				Week           string `json:"week"`            // 星期，1-7分别对应周一到周日
				Dayweather     string `json:"dayweather"`      // 白天天气现象描述
				Nightweather   string `json:"nightweather"`    // 夜间天气现象描述
				Daytemp        string `json:"daytemp"`         // 白天温度（整数）
				Nighttemp      string `json:"nighttemp"`       // 夜间温度（整数）
				Daywind        string `json:"daywind"`         // 白天风向
				Nightwind      string `json:"nightwind"`       // 夜间风向
				Daypower       string `json:"daypower"`        // 白天风力等级
				Nightpower     string `json:"nightpower"`      // 夜间风力等级
				DaytempFloat   string `json:"daytemp_float"`   // 白天温度（浮点数形式）
				NighttempFloat string `json:"nighttemp_float"` // 夜间温度（浮点数形式）
			} `json:"casts"`
		} `json:"forecasts"`
	}

	// 实时天气数据详情
	WeatherData struct {
		Province         string `json:"province"`          // 省份名称，如："北京"
		City             string `json:"city"`              // 城市名称，如："东城区"
		Adcode           string `json:"adcode"`            // 行政区划代码，如："110101"
		Weather          string `json:"weather"`           // 天气现象，如："阴"
		Temperature      string `json:"temperature"`       // 实时温度（单位：摄氏度），如："10"
		WindDirection    string `json:"winddirection"`     // 风向，如："西北"
		WindPower        string `json:"windpower"`         // 风力等级，如："6" (表示6级)
		Humidity         string `json:"humidity"`          // 空气湿度（百分比），如："24" (表示24%)
		ReportTime       string `json:"reporttime"`        // 数据发布时间，格式："2006-01-02 15:04:05"
		TemperatureFloat string `json:"temperature_float"` // 浮点型温度值，如："10.0"
		HumidityFloat    string `json:"humidity_float"`    // 浮点型湿度值，如："24.0"
	}
	//线路规划数据
	// RootResponse 是高德路线规划接口的顶层响应结构
	RootResponse struct {
		Status   string    `json:"status"`   // 接口请求状态："1" 表示成功
		Info     string    `json:"info"`     // 返回的描述信息，比如 "OK"
		Infocode string    `json:"infocode"` // 返回状态码，比如 "10000"
		Count    string    `json:"count"`    // 路径数量
		Route    *struct { // 路线详情
			Origin      string           `json:"origin"`      // 起点坐标，经纬度格式，例如 "116.466485,39.995197"
			Destination string           `json:"destination"` // 终点坐标，经纬度格式，例如 "116.46424,40.020642"
			Paths       []*DirectionPath `json:"paths"`       // 路径数组，包含多个路径方案
		} `json:"route"`
	}

	// 根结构体
	TsransitResponse struct {
		Status   string    `json:"status"`   // 状态码（"1"表示正常）
		Info     string    `json:"info"`     // 状态描述（"OK"表示成功）
		Infocode string    `json:"infocode"` // 信息编码（10000表示正常）
		Route    *struct { // 路线信息结构体（内嵌结构）
			Origin      string   `json:"origin"`      // 起点坐标（经度,纬度）
			Destination string   `json:"destination"` // 终点坐标（经度,纬度）
			Distance    string   `json:"distance"`    // 总行程距离（米）
			Cost        struct { // 费用信息结构体（内嵌结构）
				Taxi_fee string `json:"taxi_fee"` // 打车费用（元）
			} `json:"cost"`
			Transits []*Transit `json:"transits"`
		} `json:"route"`
		Count string `json:"count"` // 路线方案数量
	}
	// POIResponse 是整个接口返回的顶层结构
	POIResponse struct {
		Status   string `json:"status"`   // 返回结果状态：例如"1"表示成功
		Info     string `json:"info"`     // 返回状态说明，例如"OK"
		Infocode string `json:"infocode"` // 状态码，例如"10000"代表正确
		POIs     []struct {
			Name     string `json:"name"`     // POI名称
			ID       string `json:"id"`       // POI全局唯一ID
			Location string `json:"location"` // 经纬度坐标，格式："经度,纬度"
			Type     string `json:"type"`     // 类型描述，例如"餐饮服务|中餐厅"
			TypeCode string `json:"typecode"` // 类型编码
			PName    string `json:"pname"`    // 所在省份名称
			CityName string `json:"cityname"` // 所在城市名称
			AdName   string `json:"adname"`   // 所在区域名称（区/县）
			Address  string `json:"address"`  // 详细地址
			PCode    string `json:"pcode"`    // 省份编码
			CityCode string `json:"citycode"` // 城市编码
			AdCode   string `json:"adcode"`   // 区域编码
			Business struct {
				BusinessArea  string `json:"business_area"`            // 商圈名称
				Tel           string `json:"tel"`                      // 联系电话
				Tag           string `json:"tag"`                      // 特色标签（如"24小时营业"）
				RecTag        string `json:"rectag"`                   // 推荐标签
				KeyTag        string `json:"keytag"`                   // 关键词标签
				Rating        string `json:"rating"`                   // 综合评分
				Cost          string `json:"cost,omitempty"`           // 人均消费（可选字段）
				OpenTimeToday string `json:"opentime_today,omitempty"` // 今日营业时间（可选字段）
				OpenTimeWeek  string `json:"opentime_week,omitempty"`  // 本周营业时间（可选字段）
			} `json:"business"` // 商户相关信息
			Photos []struct {
				Title string `json:"title"` // 图片标题
				URL   string `json:"url"`   // 图片链接地址
			} `json:"photos"` // POI相关图片列表
			Distance string `json:"distance"` // 距离查询中心点的距离（米）
			Parent   string `json:"parent"`   // 上级POI ID（如有）
		} `json:"pois"` // POI列表
	}
)

var defsys ISys

func OnInit(config map[string]interface{}, option ...Option) (err error) {
	if defsys != nil {
		return
	}
	defsys, err = newSys(newOptions(config, option...))
	return
}

func NewSys(option ...Option) (sys ISys, err error) {
	sys, err = newSys(newOptionsByOption(option...))
	return
}
func Coordinate(lng, lat string) (result *LocationResponse, err error) {
	return defsys.Coordinate(lng, lat)
}

func Geo(city, addr string) (result *GeocodeResponse, err error) {
	return defsys.Geo(city, addr)
}

func Geocode(location string) (result *ReverseGeocodeResponse, err error) {
	return defsys.Geocode(location)
}

func SearchPlace(keywords string, city string) (result *SearchPlaceResponse, err error) {
	return defsys.SearchPlace(keywords, city)
}

func Weather(city, extensions string) (result *WeatherResponse, err error) {
	return defsys.Weather(city, extensions)
}
func DirectionForDriving(origin, destination string) (result *RootResponse, err error) {
	return defsys.DirectionForDriving(origin, destination)
}
func DirectionForWalking(origin, destination string) (result *RootResponse, err error) {
	return defsys.DirectionForWalking(origin, destination)
}
func DirectionForBicycling(origin, destination string) (result *RootResponse, err error) {
	return defsys.DirectionForBicycling(origin, destination)
}
func DirectionForElectrobike(origin, destination string) (result *RootResponse, err error) {
	return defsys.DirectionForElectrobike(origin, destination)
}
func DirectionForTsransit(origin, destination string, city1, city2 string) (result *TsransitResponse, err error) {
	return defsys.DirectionForTsransit(origin, destination, city1, city2)
}
func POISearch(location, radius, keywords string) (result *POIResponse, err error) {
	return defsys.POISearch(location, radius, keywords)
}
