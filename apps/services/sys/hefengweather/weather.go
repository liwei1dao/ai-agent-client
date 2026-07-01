package hefengweather

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
)

// 和风天气返回的风力等级可能是 "1-3" 这种区间值，
// AI 播报时会移除特殊符号变成 "13 级"，所以在源头取区间下限作为固定值。
func normalizeWindScale(s string) string {
	if i := strings.Index(s, "-"); i >= 0 {
		return s[:i]
	}
	return s
}

func newSys(options Options) (sys *Weather, err error) {
	sys = &Weather{
		options: options,
	}
	return
}

type Weather struct {
	options Options
}

// 搜索歌曲
func (this *Weather) CityLookup(location string) (result *CityLookupResponse, err error) {
	var (
		req  *http.Request
		resp *http.Response
		body []byte
	)
	escaped := url.QueryEscape(location)
	url := fmt.Sprintf("%s/geo/v2/city/lookup?location=%s", this.options.BaseUrl, escaped)

	req, err = http.NewRequest("GET", url, nil)
	if err != nil {
		return
	}
	req.Header.Set("X-QW-Api-Key", this.options.Key)
	// 执行请求
	client := &http.Client{}
	resp, err = client.Do(req)
	if err != nil {
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		err = fmt.Errorf("StatusCode:%d", resp.StatusCode)
	}
	// 读取响应内容
	body, err = io.ReadAll(resp.Body)
	if err != nil {
		return
	}
	// 输出响应内容
	// fmt.Println(string(body))
	result = &CityLookupResponse{}
	err = json.Unmarshal(body, result)
	return
}

// 搜索歌单
func (this *Weather) QueryWeather(location string) (result *WeatherResponse, err error) {
	var (
		req  *http.Request
		resp *http.Response
		body []byte
	)
	url := fmt.Sprintf("%s/v7/weather/7d?location=%s", this.options.BaseUrl, location)

	req, err = http.NewRequest("GET", url, nil)
	if err != nil {
		return
	}

	// 设置请求头
	req.Header.Set("X-QW-Api-Key", this.options.Key)

	// 执行请求
	client := &http.Client{}
	resp, err = client.Do(req)
	if err != nil {
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		err = fmt.Errorf("StatusCode:%d", resp.StatusCode)
	}
	// 读取响应内容
	body, err = io.ReadAll(resp.Body)
	if err != nil {
		return
	}
	// 输出响应内容
	// fmt.Println(string(body))
	result = &WeatherResponse{}
	if err = json.Unmarshal(body, result); err != nil {
		return
	}
	for i := range result.Daily {
		result.Daily[i].WindScaleDay = normalizeWindScale(result.Daily[i].WindScaleDay)
		result.Daily[i].WindScaleNight = normalizeWindScale(result.Daily[i].WindScaleNight)
	}
	return
}
