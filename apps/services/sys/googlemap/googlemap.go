package googlemap

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net/http"
	"net/url"
)

func newSys(options Options) (sys *GoogleMap, err error) {
	sys = &GoogleMap{}
	sys.options = options
	return
}

type GoogleMap struct {
	options Options
}

// 逆地理编码：根据经纬度坐标获取结构化地址
// 参数:
// - location: 坐标字符串，格式为"纬度,经度"（例如"39.90909,116.434307"）
// 返回:
// - result: 包含结构化地址与坐标的最小化结果
// - err: 请求或解析过程中产生的错误
// 异常:
// - 当请求失败或响应体解析失败时返回错误
func (this *GoogleMap) ReverseGeocode(location string) (result *ReverseGeocodeResult, err error) {
	var (
		reqURL string
		resp   *http.Response
		body   []byte
	)
	reqURL = fmt.Sprintf(
		"https://maps.googleapis.com/maps/api/geocode/json?latlng=%s&key=%s&language=zh-CN",
		url.QueryEscape(location),
		this.options.ApiKey,
	)
	if resp, err = http.Get(reqURL); err != nil {
		return
	}
	defer resp.Body.Close()
	if body, err = ioutil.ReadAll(resp.Body); err != nil {
		return
	}
	// 定义与Google返回兼容的结构体（仅取必要字段）
	var geores struct {
		Status  string `json:"status"`
		Results []struct {
			FormattedAddress string `json:"formatted_address"`
			Geometry         struct {
				Location struct {
					Lat float64 `json:"lat"`
					Lng float64 `json:"lng"`
				} `json:"location"`
			} `json:"geometry"`
		} `json:"results"`
	}
	if err = json.Unmarshal(body, &geores); err != nil {
		return
	}
	if len(geores.Results) == 0 {
		err = fmt.Errorf("no reverse geocode result")
		return
	}
	result = &ReverseGeocodeResult{
		FormattedAddress: geores.Results[0].FormattedAddress,
		Lat:              geores.Results[0].Geometry.Location.Lat,
		Lng:              geores.Results[0].Geometry.Location.Lng,
	}
	return
}

// 地理编码：根据地址获取坐标
// 参数:
// - address: 地址字符串，例如"北京市朝阳区三里屯"
// 返回:
// - result: 包含结构化地址与坐标的最小化结果
// - err: 请求或解析过程中产生的错误
func (this *GoogleMap) Geocode(address string) (result *GeocodeResult, err error) {
	var (
		reqURL string
		resp   *http.Response
		body   []byte
	)
	reqURL = fmt.Sprintf(
		"https://maps.googleapis.com/maps/api/geocode/json?address=%s&key=%s",
		url.QueryEscape(address),
		this.options.ApiKey,
	)
	if resp, err = http.Get(reqURL); err != nil {
		return
	}
	defer resp.Body.Close()
	if body, err = ioutil.ReadAll(resp.Body); err != nil {
		return
	}
	// 定义与Google返回兼容的结构体（仅取必要字段）
	var geores struct {
		Status  string `json:"status"`
		Results []struct {
			FormattedAddress string `json:"formatted_address"`
			Geometry         struct {
				Location struct {
					Lat float64 `json:"lat"`
					Lng float64 `json:"lng"`
				} `json:"location"`
			} `json:"geometry"`
		} `json:"results"`
	}
	if err = json.Unmarshal(body, &geores); err != nil {
		return
	}
	if len(geores.Results) == 0 {
		err = fmt.Errorf("no geocode result")
		return
	}
	result = &GeocodeResult{
		FormattedAddress: geores.Results[0].FormattedAddress,
		Lat:              geores.Results[0].Geometry.Location.Lat,
		Lng:              geores.Results[0].Geometry.Location.Lng,
	}
	return
}

// 范围搜索：根据坐标与半径进行附近搜索
// 参数:
// - location: 坐标字符串，格式为"纬度,经度"（例如"39.90909,116.434307"）
// - radius: 搜索半径，单位米（例如"1000"）
// - keyword: 搜索关键词（例如"餐厅"）
// 返回:
// - result: 附近搜索结果列表（最小化结构）
// - err: 请求或解析过程中产生的错误
func (this *GoogleMap) NearbySearch(location string, radius string, keyword string) (result *NearbySearchResult, err error) {
	var (
		reqURL string
		resp   *http.Response
		body   []byte
	)
	reqURL = fmt.Sprintf(
		"https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=%s&radius=%s&keyword=%s&key=%s&language=zh-CN",
		url.QueryEscape(location),
		url.QueryEscape(radius),
		url.QueryEscape(keyword),
		this.options.ApiKey,
	)
	if resp, err = http.Get(reqURL); err != nil {
		return
	}
	defer resp.Body.Close()
	if body, err = ioutil.ReadAll(resp.Body); err != nil {
		return
	}
	// 定义与Google返回兼容的结构体（仅取必要字段）
	var places struct {
		Status  string `json:"status"`
		Results []struct {
			Name     string `json:"name"`
			Vicinity string `json:"vicinity"`
			PlaceID  string `json:"place_id"`
			Rating   float64 `json:"rating"`
			Geometry struct {
				Location struct {
					Lat float64 `json:"lat"`
					Lng float64 `json:"lng"`
				} `json:"location"`
			} `json:"geometry"`
			Photos []struct {
				PhotoReference string `json:"photo_reference"`
			} `json:"photos"`
		} `json:"results"`
	}
	if err = json.Unmarshal(body, &places); err != nil {
		return
	}
	result = &NearbySearchResult{
		Items: make([]NearbyPlace, 0, len(places.Results)),
	}
	for _, r := range places.Results {
		item := NearbyPlace{
			Name:     r.Name,
			Address:  r.Vicinity,
			Lat:      r.Geometry.Location.Lat,
			Lng:      r.Geometry.Location.Lng,
			Rating:   r.Rating,
			PlaceID:  r.PlaceID,
		}
		if len(r.Photos) > 0 {
			item.PhotoRef = r.Photos[0].PhotoReference
		}
		result.Items = append(result.Items, item)
	}
	return
}

func (this *GoogleMap) Navigation(origin string, destination string, mode string) (root *RootResponse, err error) {
	// 1. 调用 Directions API
	directionsURL := fmt.Sprintf(
		"https://maps.googleapis.com/maps/api/directions/json?origin=%s&destination=%s&mode=%s&key=%s",
		url.QueryEscape(origin),
		url.QueryEscape(destination),
		url.QueryEscape(mode),
		this.options.ApiKey,
	)

	resp, err := http.Get(directionsURL)
	if err != nil {
		return
	}
	defer resp.Body.Close()

	body, _ := ioutil.ReadAll(resp.Body)

	var directions DirectionsResponse
	if err = json.Unmarshal(body, &directions); err != nil {
		return
	}

	if len(directions.Routes) == 0 {
		err = fmt.Errorf("no route found")
		return
	}

	polyline := directions.Routes[0].OverviewPolyline.Points

	// 2. 拼接 Static Maps URL
	staticMapURL := fmt.Sprintf(
		"https://maps.googleapis.com/maps/api/staticmap?size=600x400&path=enc:%s&markers=color:green|label:S|%s&markers=color:red|label:E|%s&key=%s",
		url.QueryEscape(polyline),
		url.QueryEscape(origin),
		url.QueryEscape(destination),
		this.options.ApiKey,
	)
	// mapURL := fmt.Sprintf(
	// 	"https://www.google.com/maps/dir/?api=1&origin=%s&destination=%s&travelmode=%s",
	// 	url.QueryEscape(origin),
	// 	url.QueryEscape(destination),
	// 	url.QueryEscape(mode),
	// )
	// App 深链：Google Maps 直接导航（仅支持已安装 Google Maps App 的设备）
	navURL := fmt.Sprintf(
		"google.navigation:q=%s&mode=%s",
		url.QueryEscape(destination),
		url.QueryEscape(mode),
	)

	// 3. 转换数据到RootResponse结构体
	route := directions.Routes[0]
	leg := route.Legs[0] // 取第一段路径
	startaddr := leg.StartAddress
	endaddr := leg.EndAddress
	// 创建DirectionPath
	path := &DirectionPath{
		Distance: leg.Distance.Text,
		Duration: leg.Duration.Text,
		Image:    staticMapURL,
		MapUrl:   navURL,
		Cost: struct {
			Duration string `json:"duration"`
		}{
			Duration: fmt.Sprintf("%d", leg.Duration.Value),
		},
	}

	// 转换Steps
	for _, step := range leg.Steps {
		pathStep := struct {
			Instruction  string      `json:"instruction"`
			Orientation  string      `json:"orientation"`
			RoadName     string      `json:"road_name"`
			StepDistance interface{} `json:"step_distance"`
			Navi         struct {
				Action          string `json:"action"`
				AssistantAction string `json:"assistant_action"`
				WalkType        string `json:"walk_type"`
			} `json:"navi"`
			Polyline string `json:"polyline"`
		}{
			Instruction:  step.HTMLInstructions,
			Orientation:  origin,      // Google API没有直接提供方向信息
			RoadName:     destination, // 可以从HTMLInstructions中提取
			StepDistance: step.Distance.Value,
			Navi: struct {
				Action          string `json:"action"`
				AssistantAction string `json:"assistant_action"`
				WalkType        string `json:"walk_type"`
			}{
				Action:          step.Maneuver,
				AssistantAction: "",
				WalkType:        "0",
			},
			Polyline: step.Polyline.Points,
		}
		path.Steps = append(path.Steps, pathStep)
	}

	// 创建RootResponse
	root = &RootResponse{
		Count:           "1",
		Origin:          origin,
		Destination:     destination,
		OriginAddr:      startaddr, // Google Directions API不直接提供地址
		DestinationAddr: endaddr,   // Google Directions API不直接提供地址
		Route: &struct {
			Paths []*DirectionPath `json:"paths"`
		}{
			Paths: []*DirectionPath{path},
		},
	}

	return
}
