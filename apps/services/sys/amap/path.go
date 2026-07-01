package amap

type (
	DirectionPath struct {
		Distance string   `json:"distance"` // 路径总距离，单位米
		Duration string   `json:"duration"` // 耗时
		Image    string   `json:"image"`    // 地图图片URL
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
	Transit struct { // 方案列表
		Cost struct { // 花费信息
			Duration    string `json:"duration"`    // 预计时间（秒）
			Transit_fee string `json:"transit_fee"` // 预计公共交通费用（元）
		} `json:"cost"` // 花费信息
		Distance        string    `json:"distance"`         // 该换乘路线总距离（米）
		WalkingDistance string    `json:"walking_distance"` // 步行总距离（米）
		Nightflag       string    `json:"nightflag"`        // 夜间标识（0=非夜间，1=夜间）
		Image           string    `json:"image"`            // 地图图片URL
		Segments        []Segment `json:"segments"`         // 线路分段数组（步行+公共交通）
	}
	Segment struct { // 路线分段数组（步行+公共交通）
		Walking *struct { // 步行分段（内嵌结构）
			Destination string     `json:"destination"` // 步行终点坐标
			Distance    string     `json:"distance"`    // 步行距离（米）
			Origin      string     `json:"origin"`      // 步行起点坐标
			Steps       []struct { // 步行步骤数组（内嵌结构）
				Instruction string `json:"instruction"` // 导航指令
				Road        string `json:"road"`        // 道路名称
				Distance    string `json:"distance"`    // 步骤距离（米）
				Polyline    struct {
					Polyline string `json:"polyline"` // 步行路径坐标点
				} `json:"polyline"`
				Navi struct { // 导航详细信息（内嵌结构）
					Action          string `json:"action"`           // 动作（如右转、左转）
					AssistantAction string `json:"assistant_action"` // 辅助动作（如到达站点）
					WalkType        string `json:"walk_type"`        // 步行类型（0=普通步行，5=到达终点）
				} `json:"navi"`
			} `json:"steps"`
		} `json:"walking"`
		Bus *struct { // 公共交通分段（内嵌结构，可能包含地铁/公交）
			Buslines []struct { // 线路数组（支持多线路，如地铁换乘）
				DepartureStop struct { // 起点站信息（内嵌结构）
					Name     string   `json:"name"`     // 站点名称
					ID       string   `json:"id"`       // 站点ID
					Location string   `json:"location"` // 站点坐标
					Entrance struct { // 进站口信息（仅地铁有）
						Name     string `json:"name"`     // 入口名称
						Location string `json:"location"` // 入口坐标
					} `json:"entrance,omitempty"` // 可选字段（地铁专有）
				} `json:"departure_stop"`
				ArrivalStop struct { // 到达站信息（内嵌结构）
					Name     string   `json:"name"`     // 站点名称
					ID       string   `json:"id"`       // 站点ID
					Location string   `json:"location"` // 站点坐标
					Exit     struct { // 出站口信息（仅地铁有）
						Name     string `json:"name"`     // 出口名称
						Location string `json:"location"` // 出口坐标
					} `json:"exit,omitempty"` // 可选字段（地铁专有）
				} `json:"arrival_stop"`
				Name        string      `json:"name"`          // 线路名称（如"地铁14号线"）
				ID          string      `json:"id"`            // 线路ID
				Type        string      `json:"type"`          // 线路类型（"地铁线路"/"普通公交线路"）
				Distance    string      `json:"distance"`      // 线路行驶距离（米）
				BusTimeTips string      `json:"bus_time_tips"` // 时间提示（如高峰时段）
				Bustimetag  string      `json:"bustimetag"`    // 线路时间标签
				StartTime   string      `json:"start_time"`    // 首班车时间（如"0500"表示5:00）
				EndTime     string      `json:"end_time"`      // 末班车时间（如"2300"表示23:00）
				ViaNum      interface{} `json:"via_num"`       // 途经站数量
				ViaStops    []struct {  // 途经站数组（内嵌结构）
					Name     string `json:"name"`     // 站点名称
					ID       string `json:"id"`       // 站点ID
					Location string `json:"location"` // 站点坐标
				} `json:"via_stops"`
				Polyline struct {
					Polyline string `json:"polyline"` // 步行路径坐标点
				} `json:"polyline"`
			} `json:"buslines"`
		} `json:"bus,omitempty"` // 可选字段（可能纯步行无公交）
	}
)

func (this *DirectionPath) GetPolylines() (polylines []string) {
	polylines = make([]string, 0)
	for _, step := range this.Steps {
		polylines = append(polylines, step.Polyline)
	}
	return polylines
}

func (this *Transit) GetPolylines() (polylines []string) {
	polylines = make([]string, 0)
	for _, v := range this.Segments {
		if v.Walking != nil {
			for _, step := range v.Walking.Steps {
				polylines = append(polylines, step.Polyline.Polyline)
			}
		}
		if v.Bus != nil {
			for _, busline := range v.Bus.Buslines {
				polylines = append(polylines, busline.Polyline.Polyline)
			}
		}

	}
	return polylines
}
