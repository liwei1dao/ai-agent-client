package amap

import (
	"yunyan/lego/sys/log"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"net/url"
	"strconv"
	"strings"

	"github.com/paulmach/orb"
	"github.com/paulmach/orb/simplify"
)

func newSys(options Options) (sys *Amap, err error) {
	sys = &Amap{options: options}
	return
}

type Amap struct {
	options Options
}

// 坐标转换
func (this *Amap) Coordinate(lng, lat string) (result *LocationResponse, err error) {
	var (
		req    *http.Request
		resp   *http.Response
		client *http.Client
		body   []byte
	)
	// 创建HTTP请求
	req, err = http.NewRequest("GET", fmt.Sprintf("https://restapi.amap.com/v3/assistant/coordinate/convert?locations=%s,%s&coordsys=gps&output=json&key=%s", lng, lat, this.options.Appkey), nil)
	if err != nil {
		return
	}
	// 发送请求
	client = &http.Client{}
	resp, err = client.Do(req)
	if err != nil {
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		err = fmt.Errorf("StatusCode:%d", resp.StatusCode)
	}
	// 读取响应体
	body, err = io.ReadAll(resp.Body)
	if err != nil {
		return
	}
	if resp.StatusCode != http.StatusOK {
		err = fmt.Errorf("StatusCode:%d", resp.StatusCode)
		return
	}
	result = &LocationResponse{}
	err = json.Unmarshal(body, result)
	return
}

// 搜索地址
func (this *Amap) SearchPlace(keywords string, city string) (result *SearchPlaceResponse, err error) {
	var (
		req    *http.Request
		resp   *http.Response
		client *http.Client
		body   []byte
	)
	// 创建HTTP请求
	req, err = http.NewRequest("GET", fmt.Sprintf("https://restapi.amap.com/v5/place/text?keywords=%s&types=141201&region=%s&output=JSON&key=%s", keywords, city, this.options.Appkey), nil)
	if err != nil {
		return
	}
	// 发送请求
	client = &http.Client{}
	resp, err = client.Do(req)
	if err != nil {
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		err = fmt.Errorf("StatusCode:%d", resp.StatusCode)
	}
	// 读取响应体
	body, err = io.ReadAll(resp.Body)
	if err != nil {
		return
	}
	if resp.StatusCode != http.StatusOK {
		err = fmt.Errorf("StatusCode:%d", resp.StatusCode)
		return
	}
	result = &SearchPlaceResponse{}
	err = json.Unmarshal(body, result)
	return
}

// 地理/逆地理编码
func (this *Amap) Geo(city, addr string) (result *GeocodeResponse, err error) {
	var (
		req    *http.Request
		resp   *http.Response
		client *http.Client
		body   []byte
	)
	// 创建HTTP请求
	req, err = http.NewRequest("GET", fmt.Sprintf("https://restapi.amap.com/v3/geocode/geo?city=%s&address=%s&output=JSON&key=%s", city, addr, this.options.Appkey), nil)
	if err != nil {
		return
	}
	// 发送请求
	client = &http.Client{}
	resp, err = client.Do(req)
	if err != nil {
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		err = fmt.Errorf("StatusCode:%d", resp.StatusCode)
	}
	// 读取响应体
	body, err = io.ReadAll(resp.Body)
	if err != nil {
		return
	}
	if resp.StatusCode != http.StatusOK {
		err = fmt.Errorf("StatusCode:%d", resp.StatusCode)
		return
	}
	result = &GeocodeResponse{}
	err = json.Unmarshal(body, result)
	return
}

// 逆地理编码
func (this *Amap) Geocode(location string) (result *ReverseGeocodeResponse, err error) {
	var (
		req    *http.Request
		resp   *http.Response
		client *http.Client
		body   []byte
	)
	// 创建HTTP请求
	req, err = http.NewRequest("GET", fmt.Sprintf("https://restapi.amap.com/v3/geocode/regeo?output=json&location=%s&key=%s&extensions=base", location, this.options.Appkey), nil)
	if err != nil {
		return
	}
	// 发送请求
	client = &http.Client{}
	resp, err = client.Do(req)
	if err != nil {
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		err = fmt.Errorf("StatusCode:%d", resp.StatusCode)
	}
	// 读取响应体
	body, err = io.ReadAll(resp.Body)
	if err != nil {
		return
	}
	if resp.StatusCode != http.StatusOK {
		err = fmt.Errorf("StatusCode:%d", resp.StatusCode)
		return
	}
	fmt.Println(string(body))
	result = &ReverseGeocodeResponse{}
	if err = json.Unmarshal(body, result); err != nil {
		this.options.Log.Error("Geocode Faill", log.Field{Key: "location", Value: location}, log.Field{Key: "body", Value: string(body)}, log.Field{Key: "err", Value: err})
	}
	return
}

// 天气查询
func (this *Amap) Weather(city, extensions string) (result *WeatherResponse, err error) {
	var (
		req    *http.Request
		resp   *http.Response
		client *http.Client
		body   []byte
	)
	if extensions == "" {
		extensions = "base"
	}
	// 创建HTTP请求
	req, err = http.NewRequest("GET", fmt.Sprintf("https://restapi.amap.com/v3/weather/weatherInfo?city=%s&extensions=%s&key=%s", city, extensions, this.options.Appkey), nil)
	if err != nil {
		return
	}
	// 发送请求
	client = &http.Client{}
	resp, err = client.Do(req)
	if err != nil {
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		err = fmt.Errorf("StatusCode:%d", resp.StatusCode)
	}
	// 读取响应体
	body, err = io.ReadAll(resp.Body)
	if err != nil {
		return
	}
	result = &WeatherResponse{}
	err = json.Unmarshal(body, result)
	return
}

// 步行路线规划
func (this *Amap) DirectionForDriving(origin, destination string) (result *RootResponse, err error) {
	var (
		req    *http.Request
		resp   *http.Response
		client *http.Client
		body   []byte
	)
	// 创建HTTP请求
	req, err = http.NewRequest("GET", fmt.Sprintf("https://restapi.amap.com/v5/direction/driving?isindoor=0&show_fields=cost,navi,polyline&origin=%s&destination=%s&key=%s", origin, destination, this.options.Appkey), nil)
	if err != nil {
		return
	}
	// 发送请求
	client = &http.Client{}
	resp, err = client.Do(req)
	if err != nil {
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		err = fmt.Errorf("StatusCode:%d", resp.StatusCode)
	}
	// 读取响应体
	body, err = io.ReadAll(resp.Body)
	if err != nil {
		return
	}
	if resp.StatusCode != http.StatusOK {
		err = fmt.Errorf("StatusCode:%d", resp.StatusCode)
		return
	}
	result = &RootResponse{}
	if err = json.Unmarshal(body, result); err != nil {
		return
	}
	for _, v := range result.Route.Paths {
		v.Image = this.GetMapImageUrl(result.Route.Origin, result.Route.Destination, v)
		fmt.Println(v.Image)
	}
	return
}

// 步行路线规划
func (this *Amap) DirectionForWalking(origin, destination string) (result *RootResponse, err error) {
	var (
		req    *http.Request
		resp   *http.Response
		client *http.Client
		body   []byte
	)
	// 创建HTTP请求
	req, err = http.NewRequest("GET", fmt.Sprintf("https://restapi.amap.com/v5/direction/walking?isindoor=0&show_fields=cost,navi,polyline&origin=%s&destination=%s&key=%s", origin, destination, this.options.Appkey), nil)
	if err != nil {
		return
	}
	// 发送请求
	client = &http.Client{}
	resp, err = client.Do(req)
	if err != nil {
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		err = fmt.Errorf("StatusCode:%d", resp.StatusCode)
	}
	// 读取响应体
	body, err = io.ReadAll(resp.Body)
	if err != nil {
		return
	}
	if resp.StatusCode != http.StatusOK {
		err = fmt.Errorf("StatusCode:%d", resp.StatusCode)
		return
	}
	result = &RootResponse{}
	err = json.Unmarshal(body, result)
	if err == nil && result != nil && result.Route != nil && result.Route.Paths != nil {
		for _, v := range result.Route.Paths {
			v.Image = this.GetMapImageUrl(result.Route.Origin, result.Route.Destination, v)
			// fmt.Println(v.Image)
		}
	}

	return
}

// 骑行路线规划
func (this *Amap) DirectionForBicycling(origin, destination string) (result *RootResponse, err error) {
	var (
		req    *http.Request
		resp   *http.Response
		client *http.Client
		body   []byte
	)
	// 创建HTTP请求
	req, err = http.NewRequest("GET", fmt.Sprintf("https://restapi.amap.com/v5/direction/bicycling?isindoor=0&show_fields=cost,navi,polyline&origin=%s&destination=%s&key=%s", origin, destination, this.options.Appkey), nil)
	if err != nil {
		return
	}
	// 发送请求
	client = &http.Client{}
	resp, err = client.Do(req)
	if err != nil {
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		err = fmt.Errorf("StatusCode:%d", resp.StatusCode)
	}
	// 读取响应体
	body, err = io.ReadAll(resp.Body)
	if err != nil {
		return
	}
	if resp.StatusCode != http.StatusOK {
		err = fmt.Errorf("StatusCode:%d", resp.StatusCode)
		return
	}
	result = &RootResponse{}
	err = json.Unmarshal(body, result)
	if err == nil && result != nil && result.Route != nil && result.Route.Paths != nil {
		for _, v := range result.Route.Paths {
			v.Image = this.GetMapImageUrl(result.Route.Origin, result.Route.Destination, v)
			// fmt.Println(v.Image)
		}
	}
	return
}

// 电动车路线规划
func (this *Amap) DirectionForElectrobike(origin, destination string) (result *RootResponse, err error) {
	var (
		req    *http.Request
		resp   *http.Response
		client *http.Client
		body   []byte
	)
	// 创建HTTP请求
	req, err = http.NewRequest("GET", fmt.Sprintf("https://restapi.amap.com/v5/direction/electrobike?isindoor=0&show_fields=cost,navi,polyline&origin=%s&destination=%s&key=%s", origin, destination, this.options.Appkey), nil)
	if err != nil {
		return
	}
	// 发送请求
	client = &http.Client{}
	resp, err = client.Do(req)
	if err != nil {
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		err = fmt.Errorf("StatusCode:%d", resp.StatusCode)
	}
	// 读取响应体
	body, err = io.ReadAll(resp.Body)
	if err != nil {
		return
	}
	if resp.StatusCode != http.StatusOK {
		err = fmt.Errorf("StatusCode:%d", resp.StatusCode)
		return
	}
	result = &RootResponse{}
	err = json.Unmarshal(body, result)
	if err == nil && result != nil && result.Route != nil && result.Route.Paths != nil {
		for _, v := range result.Route.Paths {
			v.Image = this.GetMapImageUrl(result.Route.Origin, result.Route.Destination, v)
			// fmt.Println(v.Image)
		}
	}
	return
}

// 公交车线路规划
func (this *Amap) DirectionForTsransit(origin, destination string, city1, city2 string) (result *TsransitResponse, err error) {
	var (
		req    *http.Request
		resp   *http.Response
		client *http.Client
		body   []byte
	)
	// 创建HTTP请求
	req, err = http.NewRequest("GET", fmt.Sprintf("https://restapi.amap.com/v5/direction/transit/integrated?isindoor=0&show_fields=cost,navi,polyline&origin=%s&destination=%s&city1=%s&city2=%s&key=%s", origin, destination, city1, city2, this.options.Appkey), nil)
	if err != nil {
		return
	}
	// 发送请求
	client = &http.Client{}
	resp, err = client.Do(req)
	if err != nil {
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		err = fmt.Errorf("StatusCode:%d", resp.StatusCode)
	}
	// 读取响应体
	body, err = io.ReadAll(resp.Body)
	if err != nil {
		return
	}
	if resp.StatusCode != http.StatusOK {
		err = fmt.Errorf("StatusCode:%d", resp.StatusCode)
		return
	}
	result = &TsransitResponse{}
	err = json.Unmarshal(body, result)
	if err == nil && result != nil && result.Route != nil && result.Route.Transits != nil {
		for _, v := range result.Route.Transits {
			v.Image = this.GetMapImageUrl(result.Route.Origin, result.Route.Destination, v)
			// fmt.Println(v.Image)
		}
	}
	return
}

// 目标搜索
func (this *Amap) POISearch(location, radius, keywords string) (result *POIResponse, err error) {
	var (
		req    *http.Request
		resp   *http.Response
		client *http.Client
		body   []byte
	)
	// 创建HTTP请求
	req, err = http.NewRequest("GET", fmt.Sprintf("https://restapi.amap.com/v5/place/around?location=%s&radius=%s&keywords=%s&show_fields=business,photos&key=%s", location, radius, keywords, this.options.Appkey), nil)
	if err != nil {
		return
	}
	// 发送请求
	client = &http.Client{}
	resp, err = client.Do(req)
	if err != nil {
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		err = fmt.Errorf("StatusCode:%d", resp.StatusCode)
	}
	// 读取响应体
	body, err = io.ReadAll(resp.Body)
	if err != nil {
		return
	}
	if resp.StatusCode != http.StatusOK {
		err = fmt.Errorf("StatusCode:%d", resp.StatusCode)
		return
	}
	result = &POIResponse{}
	err = json.Unmarshal(body, result)
	return
}

func (this *Amap) GetMapImageUrl(origin, destination string, path IPath) (mapURL string) {
	var (
		polylines []string = make([]string, 0)
		route     []LatLng
	)
	polylines = path.GetPolylines()
	route = parsePolyline(polylines)
	// 2. 解析并简化路径
	simplified := simplifyPath(route, 0.0001)
	simplified = limitPoints(simplified, 80)
	// 3. 计算地图参数
	zoom := calculateAutoZoom(simplified, 1024, 512)

	// 4. 生成静态地图URL
	mapURL = buildStaticMapURL(this.options.Appkey, simplified, zoom, origin, destination)
	return
}

// parsePolyline 解析路径点
func parsePolyline(polyline []string) []LatLng {
	var path []LatLng
	for _, step := range polyline {
		points := strings.Split(step, ";")
		for _, point := range points {
			coords := strings.Split(point, ",")
			if len(coords) != 2 {
				continue
			}
			lng, err1 := strconv.ParseFloat(coords[0], 64)
			lat, err2 := strconv.ParseFloat(coords[1], 64)
			if err1 != nil || err2 != nil {
				continue
			}
			path = append(path, LatLng{Lat: lat, Lng: lng})
		}
	}
	return path
}

// simplifyPath 使用 Douglas-Peucker 算法简化路径
func simplifyPath(points []LatLng, epsilon float64) []LatLng {
	var line orb.LineString
	for _, p := range points {
		line = append(line, orb.Point{p.Lng, p.Lat})
	}

	// 创建简化器对象
	simplifier := simplify.DouglasPeucker(epsilon)

	// 使用简化器简化路径
	simplified := simplifier.Simplify(line).(orb.LineString)

	var result []LatLng
	for _, p := range simplified {
		result = append(result, LatLng{Lat: p[1], Lng: p[0]})
	}
	return result
}

// calculateAutoZoom 计算适合的缩放级别
func calculateAutoZoom(points []LatLng, mapWidth, mapHeight int) int {
	if len(points) == 0 {
		return 15 // 默认缩放级别
	}

	minLat, maxLat := points[0].Lat, points[0].Lat
	minLng, maxLng := points[0].Lng, points[0].Lng

	for _, p := range points {
		if p.Lat < minLat {
			minLat = p.Lat
		}
		if p.Lat > maxLat {
			maxLat = p.Lat
		}
		if p.Lng < minLng {
			minLng = p.Lng
		}
		if p.Lng > maxLng {
			maxLng = p.Lng
		}
	}

	latFraction := (latRad(maxLat) - latRad(minLat)) / math.Pi
	lngDiff := maxLng - minLng
	if lngDiff < 0 {
		lngDiff += 360
	}
	lngFraction := lngDiff / 360

	latZoom := math.Log2(float64(mapHeight) / 256 / latFraction)
	lngZoom := math.Log2(float64(mapWidth) / 256 / lngFraction)

	zoom := int(math.Min(latZoom, lngZoom))
	if zoom > 18 {
		zoom = 18
	}
	return zoom
}

func latRad(lat float64) float64 {
	sin := math.Sin(lat * math.Pi / 180)
	return math.Log((1+sin)/(1-sin)) / 2
}
func limitPoints(points []LatLng, max int) []LatLng {
	if len(points) <= max {
		return points
	}
	step := float64(len(points)) / float64(max)
	var result []LatLng
	for i := 0; i < max; i++ {
		index := int(math.Round(float64(i) * step))
		if index >= len(points) {
			index = len(points) - 1
		}
		result = append(result, points[index])
	}
	return result
}

// 获取静态地图
func buildStaticMapURL(apiKey string, path []LatLng, zoom int, origin, destination string) string {
	var pathParam strings.Builder

	for i, p := range path {
		if i > 0 {
			pathParam.WriteString(";")
		}
		pathParam.WriteString(fmt.Sprintf("%f,%f", p.Lng, p.Lat))
	}

	markers := fmt.Sprintf("mid,,A:%s|mid,,B:%s", origin, destination)

	params := url.Values{}
	params.Set("zoom", fmt.Sprintf("%d", zoom))
	params.Set("size", "1024*512")
	params.Set("paths", fmt.Sprintf("10,0x0000ff,1,,:%s", pathParam.String()))
	params.Set("markers", markers)
	params.Set("key", apiKey)

	return fmt.Sprintf("https://restapi.amap.com/v3/staticmap?%s", params.Encode())
}
