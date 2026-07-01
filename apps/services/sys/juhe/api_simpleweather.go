package juhe

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
)

const (
	// 基本参数配置
	simpleWeather_apiUrl = "http://apis.juhe.cn/simpleWeather/query"
)

type (
	WeatherResponse struct {
		Reason    string `json:"reason"`
		Result    Result `json:"result"`
		ErrorCode int    `json:"error_code"`
	}

	Result struct {
		City     string   `json:"city"`
		Realtime Realtime `json:"realtime"`
		Future   []Future `json:"future"`
	}

	Realtime struct {
		Temperature string `json:"temperature"` //温度，可能为空
		Humidity    string `json:"humidity"`    //湿度，可能为空
		Info        string `json:"info"`        //天气情况，如：晴、多云
		Wid         string `json:"wid"`         //天气标识id，可参考小接口2
		Direct      string `json:"direct"`      //风向，可能为空
		Power       string `json:"power"`       //风力，可能为空
		Aqi         string `json:"aqi"`         //空气质量指数，可能为空
	}

	Future struct {
		Date        string `json:"date"`
		Temperature string `json:"temperature"`
		Weather     string `json:"weather"`
		Wid         Wid    `json:"wid"`
		Direct      string `json:"direct"`
	}

	Wid struct {
		Day   string `json:"day"`
		Night string `json:"night"`
	}
)

/*
简单天气查询
*/
func (this *JuHe) SimpleWeather(city string) (result *WeatherResponse, err error) {
	requestParams := url.Values{}
	requestParams.Set("key", this.options.SimpleWeather_ApiKey)
	requestParams.Set("city", city)

	// 发起接口网络请求
	resp, err := http.Get(simpleWeather_apiUrl + "?" + requestParams.Encode())
	if err != nil {
		return
	}
	defer resp.Body.Close()
	result = &WeatherResponse{}

	if err = json.NewDecoder(resp.Body).Decode(result); err != nil {
		return
	}
	if result.ErrorCode != 0 {
		err = fmt.Errorf("ErrorCode:%d", result.ErrorCode)
	}
	return
}
