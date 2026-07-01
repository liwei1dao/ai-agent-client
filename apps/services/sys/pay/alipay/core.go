package alipay

import (
	"context"
	"net/url"
)

type (
	// 预支付响应参数（返回给Flutter客户端）
	AppPayParams struct {
		AppID     string `json:"appid"`     // 应用ID
		PartnerID string `json:"partnerid"` // 商户号
		PrepayID  string `json:"prepayid"`  // 预支付ID
		Package   string `json:"package"`   // 固定值 "Sign=WXPay"
		NonceStr  string `json:"noncestr"`  // 随机字符串
		TimeStamp string `json:"timestamp"` // 时间戳（秒）
		Sign      string `json:"sign"`      // 支付签名
	}

	ISys interface {
		GenerateOrderNo(prefix string) string
		CreateAppOrder(ctx context.Context, outTradeNo string, totalFee int64, description string, notifyurl string) (result string, err error)
		DecryptWxPayNotify(values url.Values) (bool, error)
	}
)

var defsys ISys

func OnInit(config map[string]interface{}, option ...Option) (err error) {
	defsys, err = newSys(newOptions(config, option...))
	return
}

func NewSys(option ...Option) (sys ISys, err error) {
	sys, err = newSys(newOptionsByOption(option...))
	return
}

func GenerateOrderNo(prefix string) string {
	return defsys.GenerateOrderNo(prefix)
}

func CreateAppOrder(ctx context.Context, outTradeNo string, totalFee int64, description string, notifyurl string) (result string, err error) {
	return defsys.CreateAppOrder(ctx, outTradeNo, totalFee, description, notifyurl)
}

func DecryptWxPayNotify(values url.Values) (bool, error) {
	return defsys.DecryptWxPayNotify(values)
}
