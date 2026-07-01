package qweather_test

import (
	"fmt"
	"io/ioutil"
	"net/http"
	"os"
	"testing"
	"yunyan/sys/qweather"
)

func Test_api(t *testing.T) {
	apiKey := os.Getenv("QWEATHER_API_KEY")
	apiHost := os.Getenv("QWEATHER_API_HOST")
	if apiKey == "" || apiHost == "" {
		t.Skip("QWEATHER_API_KEY / QWEATHER_API_HOST env not set")
	}
	// 请求的URL
	url := fmt.Sprintf("https://%s/geo/v2/city/lookup?location=北京", apiHost)

	// 创建一个新的HTTP请求
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		fmt.Println("创建请求失败:", err)
		return
	}

	// 设置请求头，包含API密钥
	req.Header.Set("User-Agent", "Apifox/1.0.0 (https://apifox.com)")
	req.Header.Set("X-QW-Api-Key", apiKey)
	req.Header.Set("Accept-Encoding", "gzip, deflate, br")

	// 创建一个HTTP客户端并发送请求
	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		fmt.Println("请求失败:", err)
		return
	}
	defer resp.Body.Close() // 确保响应体被关闭

	// 读取响应体
	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		fmt.Println("读取响应体失败:", err)
		return
	}

	// 打印响应状态码和响应体
	fmt.Printf("响应状态码: %d\n", resp.StatusCode)
	fmt.Printf("响应体: %s\n", body)
}
func Test_Sys_GeoApi(t *testing.T) {
	apiKey := os.Getenv("QWEATHER_API_KEY")
	apiHost := os.Getenv("QWEATHER_API_HOST")
	if apiKey == "" || apiHost == "" {
		t.Skip("QWEATHER_API_KEY / QWEATHER_API_HOST env not set")
	}
	if sys, err := qweather.NewSys(
		qweather.SetApiHost(apiHost),
		qweather.SetApiKey(apiKey),
	); err != nil {
		fmt.Printf("Sys Init err:%v", err)
	} else {
		result, err := sys.GeoApi("北京")
		fmt.Printf("result:%v err:%v", result, err)
	}
}
