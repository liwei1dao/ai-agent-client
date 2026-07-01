package qweather

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"

	"github.com/coze-dev/coze-go"
)

func newSys(options Options) (sys *QWeather, err error) {
	sys = &QWeather{
		options: options,
	}

	return
}

type QWeather struct {
	options Options
	api     coze.CozeAPI
}

// 城市查询
func (this *QWeather) GeoApi(location string) (result *WeatherLocationResponse, err error) {
	var (
		req  *http.Request
		resp *http.Response
		body []byte
	)
	// 创建GET请求
	req, err = http.NewRequest("GET", fmt.Sprintf("https://%s/geo/v2/city/lookup?location=%s", this.options.ApiHost, location), nil)
	if err != nil {
		return
	}
	// 设置请求头
	req.Header.Set("X-QW-Api-Key", fmt.Sprintf("Bearer %s", this.options.ApiKey))
	req.Header.Set("Accept-Encoding", "gzip, deflate, br, zstd") // 模拟cURL的--compressed选项

	// 发送请求
	client := &http.Client{}
	resp, err = client.Do(req)
	if err != nil {
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		err = fmt.Errorf("StatusCode:%d", resp.StatusCode)
		return
	}
	// 读取并处理响应
	body, err = io.ReadAll(resp.Body)
	if err != nil {
		return
	}
	result = &WeatherLocationResponse{}
	err = json.Unmarshal(body, result)
	return
}

// 天气查询
func (this *QWeather) Weather(location string) (result *WeatherResponse, err error) {
	var (
		req  *http.Request
		resp *http.Response
		body []byte
	)
	// 创建GET请求
	req, err = http.NewRequest("GET", fmt.Sprintf("https://%s/v7/weather/now?location:%s", this.options.ApiHost, location), nil)
	if err != nil {
		return
	}
	// 设置请求头
	req.Header.Set("X-QW-Api-Key", fmt.Sprintf("Bearer %s", this.options.ApiKey))
	req.Header.Set("Accept-Encoding", "gzip, deflate, br, zstd") // 模拟cURL的--compressed选项

	// 发送请求
	client := &http.Client{}
	resp, err = client.Do(req)
	if err != nil {
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		err = fmt.Errorf("StatusCode:%d", resp.StatusCode)
		return
	}
	// 读取并处理响应
	body, err = io.ReadAll(resp.Body)
	if err != nil {
		return
	}
	result = &WeatherResponse{}
	err = json.Unmarshal(body, result)
	return
}
