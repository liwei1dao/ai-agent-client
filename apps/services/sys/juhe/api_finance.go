package juhe

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
)

const (
	finance_apiUrl = "http://web.juhe.cn/finance/stock/hs"
)

type (
	//股票查询数据
	StockResponse struct {
		ResultCode    string          `json:"resultcode"` // 返回码，200:正常
		Reason        string          `json:"reason"`     // 返回原因
		FinanceResult []FinanceResult `json:"result"`     // 股票数据
	}

	FinanceResult struct {
		Data      StockData `json:"data"`      // 股票详细信息
		Dapandata DapanData `json:"dapandata"` // 大盘数据
		Gopicture GoPicture `json:"gopicture"` // K线图URL
	}

	StockData struct {
		Gid            string `json:"gid"`            // 股票编号
		IncrePer       string `json:"increPer"`       // 涨跌百分比
		Increase       string `json:"increase"`       // 涨跌额
		Name           string `json:"name"`           // 股票名称
		TodayStartPri  string `json:"todayStartPri"`  // 今日开盘价
		YestodEndPri   string `json:"yestodEndPri"`   // 昨日收盘价
		NowPri         string `json:"nowPri"`         // 当前价格
		TodayMax       string `json:"todayMax"`       // 今日最高价
		TodayMin       string `json:"todayMin"`       // 今日最低价
		CompetitivePri string `json:"competitivePri"` // 竞买价
		ReservePri     string `json:"reservePri"`     // 竞卖价
		TraNumber      string `json:"traNumber"`      // 成交量
		TraAmount      string `json:"traAmount"`      // 成交金额
		BuyOne         string `json:"buyOne"`         // 买一
		BuyOnePri      string `json:"buyOnePri"`      // 买一报价
		BuyTwo         string `json:"buyTwo"`         // 买二
		BuyTwoPri      string `json:"buyTwoPri"`      // 买二报价
		BuyThree       string `json:"buyThree"`       // 买三
		BuyThreePri    string `json:"buyThreePri"`    // 买三报价
		BuyFour        string `json:"buyFour"`        // 买四
		BuyFourPri     string `json:"buyFourPri"`     // 买四报价
		BuyFive        string `json:"buyFive"`        // 买五
		BuyFivePri     string `json:"buyFivePri"`     // 买五报价
		SellOne        string `json:"sellOne"`        // 卖一
		SellOnePri     string `json:"sellOnePri"`     // 卖一报价
		SellTwo        string `json:"sellTwo"`        // 卖二
		SellTwoPri     string `json:"sellTwoPri"`     // 卖二报价
		SellThree      string `json:"sellThree"`      // 卖三
		SellThreePri   string `json:"sellThreePri"`   // 卖三报价
		SellFour       string `json:"sellFour"`       // 卖四
		SellFourPri    string `json:"sellFourPri"`    // 卖四报价
		SellFive       string `json:"sellFive"`       // 卖五
		SellFivePri    string `json:"sellFivePri"`    // 卖五报价
		Date           string `json:"date"`           // 日期
		Time           string `json:"time"`           // 时间
	}

	DapanData struct {
		Dot       string `json:"dot"`       // 当前价格
		Name      string `json:"name"`      // 名称
		NowPic    string `json:"nowPic"`    // 涨量
		Rate      string `json:"rate"`      // 涨幅(%)
		TraAmount string `json:"traAmount"` // 成交额(万)
		TraNumber string `json:"traNumber"` // 成交量
	}

	GoPicture struct {
		MinURL   string `json:"minurl"`   // 分时K线图
		DayURL   string `json:"dayurl"`   // 日K线图
		WeekURL  string `json:"weekurl"`  // 周K线图
		MonthURL string `json:"monthurl"` // 月K线图
	}

	IndexResponse struct {
		ErrorCode int       `json:"error_code"` // 错误码
		Reason    string    `json:"reason"`     // 返回原因
		Result    IndexData `json:"result"`     // 指数数据
	}

	IndexData struct {
		DealNum  string `json:"dealNum"`  // 成交量(手)
		DealPri  string `json:"dealPri"`  // 成交额
		HighPri  string `json:"highPri"`  // 最高
		IncrePer string `json:"increPer"` // 涨跌百分比
		Increase string `json:"increase"` // 涨跌幅
		LowPri   string `json:"lowpri"`   // 最低
		Name     string `json:"name"`     // 名称
		NowPri   string `json:"nowpri"`   // 当前价格
		OpenPri  string `json:"openPri"`  // 今开
		Time     string `json:"time"`     // 时间
		YesPri   string `json:"yesPri"`   // 昨收
	}
)

/*
股票查询 具体股票代码
*/
func (this *JuHe) Financebygid(gid string) (result *StockResponse, err error) {
	// 基本参数配置
	// apiUrl := "http://web.juhe.cn/finance/stock/hs"
	// apiKey := "<from options.Finance_ApiKey>"
	// 接口请求入参配置
	requestParams := url.Values{}
	requestParams.Set("key", this.options.Finance_ApiKey)
	requestParams.Set("gid", gid)
	// 发起接口网络请求
	resp, err := http.Get(finance_apiUrl + "?" + requestParams.Encode())
	if err != nil {
		return
	}
	defer resp.Body.Close()
	result = &StockResponse{}
	err = json.NewDecoder(resp.Body).Decode(&result)
	return
}

/*
股票查询 0代表上证综合指数，1代表深证成份指数
*/
func (this *JuHe) Financebytype(ftype string) (result *IndexResponse, err error) {
	// 基本参数配置
	// apiUrl := "http://web.juhe.cn/finance/stock/hs"
	// apiKey := "<from options.Finance_ApiKey>"
	// 接口请求入参配置
	requestParams := url.Values{}
	requestParams.Set("key", this.options.Finance_ApiKey)
	requestParams.Set("type", ftype)
	// 发起接口网络请求
	resp, err := http.Get(finance_apiUrl + "?" + requestParams.Encode())
	if err != nil {
		return
	}
	defer resp.Body.Close()
	result = &IndexResponse{}
	if err = json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return
	}
	if result.ErrorCode != 0 {
		err = fmt.Errorf("ErrorCode:%d", result.ErrorCode)
	}
	return
}
