package music

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
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
	keywords = url.QueryEscape(keywords)
	url := fmt.Sprintf("%s/cloudsearch?keywords=%s&limit=%d&offset=%d", this.options.ApiBaseUrl, keywords, limit, offset)

	req, err = http.NewRequest("GET", url, nil)
	if err != nil {
		return
	}

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

// 搜索歌单
func (this *Music) SearchMusicList(keywords string, limit, offset int) (result *PlaylistSearchResponse, err error) {
	var (
		req  *http.Request
		resp *http.Response
		body []byte
	)
	keywords = url.QueryEscape(keywords)
	url := fmt.Sprintf("%s/search?type=1000&keywords=%s&limit=%d&offset=%d", this.options.ApiBaseUrl, keywords, limit, offset)

	req, err = http.NewRequest("GET", url, nil)
	if err != nil {
		return
	}

	// 设置请求头
	req.Header.Set("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7")
	req.Header.Set("Accept-Language", "zh-CN,zh;q=0.9")
	req.Header.Set("Cache-Control", "no-cache")
	req.Header.Set("Connection", "keep-alive")
	req.Header.Set("Pragma", "no-cache")
	req.Header.Set("Sec-Fetch-Dest", "document")
	req.Header.Set("Sec-Fetch-Mode", "navigate")
	req.Header.Set("Sec-Fetch-Site", "none")
	req.Header.Set("Sec-Fetch-User", "?1")
	req.Header.Set("Upgrade-Insecure-Requests", "1")
	req.Header.Set("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36")
	req.Header.Set("sec-ch-ua", `"Google Chrome";v="135", "Not-A.Brand";v="8", "Chromium";v="135"`)
	req.Header.Set("sec-ch-ua-mobile", "?0")
	req.Header.Set("sec-ch-ua-platform", `"macOS"`)

	// 设置 Cookie
	req.Header.Set("Cookie", this.options.Cookie)

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
	result = &PlaylistSearchResponse{}
	err = json.Unmarshal(body, result)
	return
}

// 歌单详情
func (this *Music) MusicListDetail(id int64, limit, offset int) (result *MusicListDetailResponse, err error) {
	var (
		req  *http.Request
		resp *http.Response
		body []byte
	)
	url := fmt.Sprintf("%s/playlist/track/all?id=%d&limit=%d&offset=%d", this.options.ApiBaseUrl, id, limit, offset)
	req, err = http.NewRequest("GET", url, nil)
	if err != nil {
		return
	}

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
	}
	// 打印结果
	fmt.Println(string(body))
	result = &MusicListDetailResponse{}
	err = json.Unmarshal(body, result)
	return
}

// 音乐连接获取
func (this *Music) MusicUrl(id int64) (result *UrlResult, err error) {
	var (
		req  *http.Request
		resp *http.Response
		body []byte
	)

	url := fmt.Sprintf("%s/song/url/unblock?id=%d", this.options.ApiBaseUrl, id)
	req, err = http.NewRequest("GET", url, nil)
	if err != nil {
		return
	}

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
	// fmt.Println(string(body))
	result = &UrlResult{}
	err = json.Unmarshal(body, result)
	return
}
