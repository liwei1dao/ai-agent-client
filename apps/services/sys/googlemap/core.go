package googlemap

type (
	ISys interface {
		Navigation(origin string, destination string, mode string) (root *RootResponse, err error)
		// 地理编码：根据地址获取坐标
		Geocode(address string) (result *GeocodeResult, err error)
		// 逆地理编码：根据经纬度坐标获取结构化地址
		// 参数:
		//   - location: 坐标字符串，格式为"纬度,经度"（例如"39.90909,116.434307"）
		//
		// 返回值:
		//   - result: ReverseGeocodeResult 最小结构
		//   - err: 请求或解析过程中的错误
		//
		// 异常:
		//   - 当请求失败或响应体解析失败时返回错误
		ReverseGeocode(location string) (result *ReverseGeocodeResult, err error)
		// 范围搜索：根据坐标与半径进行附近搜索
		NearbySearch(location string, radius string, keyword string) (result *NearbySearchResult, err error)
	}
	DirectionsResponse struct {
		GeocodedWaypoints []struct {
			GeocoderStatus string   `json:"geocoder_status"`
			PlaceID        string   `json:"place_id"`
			Types          []string `json:"types"`
		} `json:"geocoded_waypoints"`

		Routes []struct {
			Bounds struct {
				Northeast struct {
					Lat float64 `json:"lat"`
					Lng float64 `json:"lng"`
				} `json:"northeast"`
				Southwest struct {
					Lat float64 `json:"lat"`
					Lng float64 `json:"lng"`
				} `json:"southwest"`
			} `json:"bounds"`

			Copyrights string `json:"copyrights"`

			Legs []struct {
				Distance struct {
					Text  string `json:"text"`
					Value int    `json:"value"`
				} `json:"distance"`

				Duration struct {
					Text  string `json:"text"`
					Value int    `json:"value"`
				} `json:"duration"`

				EndAddress  string `json:"end_address"`
				EndLocation struct {
					Lat float64 `json:"lat"`
					Lng float64 `json:"lng"`
				} `json:"end_location"`

				StartAddress  string `json:"start_address"`
				StartLocation struct {
					Lat float64 `json:"lat"`
					Lng float64 `json:"lng"`
				} `json:"start_location"`

				Steps []struct {
					Distance struct {
						Text  string `json:"text"`
						Value int    `json:"value"`
					} `json:"distance"`

					Duration struct {
						Text  string `json:"text"`
						Value int    `json:"value"`
					} `json:"duration"`

					EndLocation struct {
						Lat float64 `json:"lat"`
						Lng float64 `json:"lng"`
					} `json:"end_location"`

					StartLocation struct {
						Lat float64 `json:"lat"`
						Lng float64 `json:"lng"`
					} `json:"start_location"`

					HTMLInstructions string `json:"html_instructions"`

					Maneuver string `json:"maneuver,omitempty"`

					Polyline struct {
						Points string `json:"points"`
					} `json:"polyline"`

					TravelMode string `json:"travel_mode"`
				} `json:"steps"`

				TrafficSpeedEntry []interface{} `json:"traffic_speed_entry"`
				ViaWaypoint       []interface{} `json:"via_waypoint"`
			} `json:"legs"`

			OverviewPolyline struct {
				Points string `json:"points"`
			} `json:"overview_polyline"`

			Summary       string   `json:"summary"`
			Warnings      []string `json:"warnings"`
			WaypointOrder []int    `json:"waypoint_order"`
		} `json:"routes"`

		Status string `json:"status"`
	}
	//线路规划数据
	// RootResponse 是高德路线规划接口的顶层响应结构
	RootResponse struct {
		Count           string    `json:"count"`           // 路径数量
		Origin          string    `json:"origin"`          // 起点坐标，经纬度格式，例如 "116.466485,39.995197"
		Destination     string    `json:"destination"`     // 终点坐标，经纬度格式，例如 "116.46424,40.020642"
		OriginAddr      string    `json:"originaddr"`      // 起点地址
		DestinationAddr string    `json:"destinationaddr"` // 目标点地址
		Route           *struct { // 路线详情
			Paths []*DirectionPath `json:"paths"` // 路径数组，包含多个路径方案
		} `json:"route"`
	}
	DirectionPath struct {
		Distance string   `json:"distance"` // 路径总距离，单位米
		Duration string   `json:"duration"` // 耗时
		Image    string   `json:"image"`    // 地图图片URL
		MapUrl   string   `json:"map_url"`  // 路径地图链接
		Cost     struct { // 花费信息
			Duration string `json:"duration"` // 路线预计步行时间，单位秒
		} `json:"cost"`
		Steps []struct { // 每一步的导航指令列表
			Instruction  string      `json:"instruction"`   // 导航指令描述，例如 "向北步行15米右转"
			Orientation  string      `json:"orientation"`   // 当前方向，例如 "北"
			RoadName     string      `json:"road_name"`     // 道路名称
			StepDistance interface{} `json:"step_distance"` // 本步行段的距离，单位米
			Navi         struct {    // 导航动作细节
				Action          string `json:"action"`           // 主要动作，例如"右转"
				AssistantAction string `json:"assistant_action"` // 辅助动作，例如"到达目的地"
				WalkType        string `json:"walk_type"`        // 步行类型（通常是0）
			} `json:"navi"`
			Polyline string `json:"polyline"` // 路径坐标点，格式为 "经度1,纬度1;经度2,纬度2"
		} `json:"steps"`
	}
	// 地理编码结果（最小化结构）
	GeocodeResult struct {
		FormattedAddress string  `json:"formatted_address"` // 结构化地址
		Lat              float64 `json:"lat"`               // 纬度
		Lng              float64 `json:"lng"`               // 经度
	}
	// 逆地理编码结果（最小化结构）
	ReverseGeocodeResult struct {
		FormattedAddress string  `json:"formatted_address"` // 结构化地址
		Lat              float64 `json:"lat"`               // 纬度
		Lng              float64 `json:"lng"`               // 经度
	}
	// 附近搜索单条结果（最小化结构）
	NearbyPlace struct {
		Name     string  `json:"name"`      // 名称
		Address  string  `json:"address"`   // 地址/附近信息
		Lat      float64 `json:"lat"`       // 纬度
		Lng      float64 `json:"lng"`       // 经度
		Rating   float64 `json:"rating"`    // 评分
		PlaceID  string  `json:"place_id"`  // Place 唯一ID
		PhotoRef string  `json:"photo_ref"` // 照片引用（可能为空）
	}
	// 附近搜索结果（最小化结构）
	NearbySearchResult struct {
		Items []NearbyPlace `json:"items"`
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

func Navigation(origin string, destination string, mode string) (root *RootResponse, err error) {
	return defsys.Navigation(origin, destination, mode)
}

// 地理编码：根据地址获取坐标
func Geocode(address string) (result *GeocodeResult, err error) {
	return defsys.Geocode(address)
}

// 逆地理编码：根据经纬度坐标获取结构化地址
// 参数:
//   - location: 坐标字符串，格式为"纬度,经度"（例如"39.90909,116.434307"）
//
// 返回值:
//   - result: ReverseGeocodeResult 最小结构
//   - err: 请求或解析过程中的错误
//
// 异常:
//   - 当请求失败或响应体解析失败时返回错误
func ReverseGeocode(location string) (result *ReverseGeocodeResult, err error) {
	return defsys.ReverseGeocode(location)
}

// 范围搜索：根据坐标与半径进行附近搜索
func NearbySearch(location string, radius string, keyword string) (result *NearbySearchResult, err error) {
	return defsys.NearbySearch(location, radius, keyword)
}
