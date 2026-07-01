package music_test

import (
	"yunyan/sys/music"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"testing"
	"time"
)

// Test_SearchMusic 调用外部音乐搜索接口做最小联通性验证。
// 参数:
//   - t: Go 测试对象
//
// 返回值:
//   - 无
//
// 异常:
//   - 当未启用集成测试时跳过
//   - 当外部接口不可用或返回异常时，测试失败
func Test_SearchMusic(t *testing.T) {
	if os.Getenv("MUSIC_INTEGRATION_TEST") == "" {
		t.Skip("跳过测试：未设置环境变量 MUSIC_INTEGRATION_TEST")
	}
	keywords := url.QueryEscape("泡沫")
	url := fmt.Sprintf("http://api.ideapsound.com:3000/cloudsearch?keywords=%s&limit=1&offset=0", keywords)

	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		t.Fatalf("构造请求失败: %v", err)
	}
	// 执行请求
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		t.Fatalf("请求失败: %v", err)
	}
	defer resp.Body.Close()

	// 读取响应内容
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("读取响应失败: %v", err)
	}

	// 输出响应内容
	fmt.Println(string(body))
}

// Test_Sys_SearchMusic 使用系统封装进行音乐 URL 获取的最小集成测试。
// 参数:
//   - t: Go 测试对象
//
// 返回值:
//   - 无
//
// 异常:
//   - 当未启用集成测试时跳过
//   - 当请求失败时，测试失败
func Test_Sys_SearchMusic(t *testing.T) {
	if os.Getenv("MUSIC_INTEGRATION_TEST") == "" {
		t.Skip("跳过测试：未设置环境变量 MUSIC_INTEGRATION_TEST")
	}
	if sys, err := music.NewSys(
		music.SetApiBaseUrl("https://music.voitrans.net"),
	); err != nil {
		t.Fatalf("Sys Init err:%v", err)
	} else {
		var (
			searchResultResponse *music.UrlResult
		)
		if searchResultResponse, err = sys.MusicUrl(441491828); err == nil {

		}
		if err != nil {
			t.Fatalf("播放音乐失败: %v", err)
		}
		t.Logf("播放音乐成功 searchResultResponse:%+v", searchResultResponse)
	}
}
