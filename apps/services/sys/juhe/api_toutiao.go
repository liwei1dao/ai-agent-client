package juhe

import (
	"encoding/json"
	"net/http"
	"net/url"
)

const (
	toutiao_api = "http://v.juhe.cn/toutiao/index"
)

type (
	NewsResponse struct {
		Reason    string        `json:"reason"`     // 返回原因
		Result    ToutiaoResult `json:"result"`     // 返回结果
		ErrorCode int           `json:"error_code"` // 错误码
	}

	ToutiaoResult struct {
		Stat     string `json:"stat"`     // 状态码
		Data     []News `json:"data"`     // 新闻数据
		Page     string `json:"page"`     // 当前页码
		PageSize string `json:"pageSize"` // 每页大小
	}

	News struct {
		UniqueKey       string `json:"uniquekey"`         // 唯一标识
		Title           string `json:"title"`             // 新闻标题
		Date            string `json:"date"`              // 发布日期
		Category        string `json:"category"`          // 新闻类别
		AuthorName      string `json:"author_name"`       // 作者名称
		URL             string `json:"url"`               // 新闻链接
		ThumbnailPicS   string `json:"thumbnail_pic_s"`   // 缩略图1
		ThumbnailPicS02 string `json:"thumbnail_pic_s02"` // 缩略图2
		ThumbnailPicS03 string `json:"thumbnail_pic_s03"` // 缩略图3
		IsContent       string `json:"is_content"`        // 是否有内容
	}
)

/*
股票查询 具体股票代码
*/
func (this *JuHe) Toutiao(ntype string) (result *NewsResponse, err error) {
	// 接口请求入参配置
	requestParams := url.Values{}
	requestParams.Set("key", this.options.Toutiao_ApiKey)
	requestParams.Set("type", ntype)
	requestParams.Set("page", "1")
	requestParams.Set("page_size", "10")
	requestParams.Set("is_filter", "0")

	// 发起接口网络请求
	resp, err := http.Get(toutiao_api + "?" + requestParams.Encode())
	if err != nil {
		return
	}
	defer resp.Body.Close()
	result = &NewsResponse{}
	err = json.NewDecoder(resp.Body).Decode(result)
	return
}
