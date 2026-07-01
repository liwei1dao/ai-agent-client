package musicobj

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
)

func newSys(options Options) (sys *Music, err error) {
	sys = &Music{
		options: options,
	}
	return
}

type Music struct {
	options Options
}

// 搜索歌曲
func (this *Music) SearchMusic(keywords string, limit, offset int) (result *SearchResultResponse, err error) {
	var (
		req  *http.Request
		resp *http.Response
		body []byte
	)
	// keywords = url.QueryEscape(keywords)

	// 创建JSON请求体
	requestData := map[string]interface{}{
		"keywords": keywords,
		"limit":    limit,
		"offset":   offset,
	}
	url := fmt.Sprintf("%s/api/music/music_search", this.options.ApiBaseUrl)

	jsonData, err := json.Marshal(requestData)
	if err != nil {
		return
	}

	req, err = http.NewRequest("POST", url, bytes.NewBuffer(jsonData))
	if err != nil {
		return
	}
	// 设置请求头
	req.Header.Set("Content-Type", "application/json")
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
	result = &SearchResultResponse{}
	err = json.Unmarshal(body, result)
	return
}

// 音乐连接获取
func (this *Music) MusicUrl(id int64) (result *UrlResultResponse, err error) {
	var (
		req  *http.Request
		resp *http.Response
		body []byte
	)
	// 创建JSON请求体
	requestData := map[string]interface{}{
		"id": id,
	}
	jsonData, err := json.Marshal(requestData)
	if err != nil {
		return
	}
	url := fmt.Sprintf("%s/api/music/music_url", this.options.ApiBaseUrl)
	req, err = http.NewRequest("POST", url, bytes.NewBuffer(jsonData))
	if err != nil {
		return
	}

	// 设置请求头
	req.Header.Set("Content-Type", "application/json")
	// 发起请求
	client := &http.Client{}
	resp, err = client.Do(req)
	if err != nil {
		return
	}
	defer resp.Body.Close()

	// 读取响应内容
	body, err = io.ReadAll(resp.Body)
	if err != nil {
		return
	}
	if resp.StatusCode != http.StatusOK {
		err = fmt.Errorf("StatusCode:%d", resp.StatusCode)
		return
	}
	// 打印结果
	fmt.Println(string(body))
	result = &UrlResultResponse{}
	err = json.Unmarshal(body, result)
	return
}
