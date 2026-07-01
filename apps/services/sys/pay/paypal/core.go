package paypal

import (
	"context"
)

type (
	// App端需要的关键参数（示例：返回订单ID与跳转链接）
	AppPayParams struct {
		OrderID     string `json:"order_id"`
		ApproveLink string `json:"approve_link"`
	}

	ISys interface {
		GenerateOrderNo(prefix string) string
		CreateAppOrder(ctx context.Context, outTradeNo string, totalFee int64, description string, return_url string, cancel_url string) (result string, err error)
		CaptureOrder(ctx context.Context, orderID string) (result string, err error)
		VerifyWebhook(headers map[string]string, body []byte) (bool, error)
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

func CreateAppOrder(ctx context.Context, outTradeNo string, totalFee int64, description string, return_url string, cancel_url string) (result string, err error) {
	return defsys.CreateAppOrder(ctx, outTradeNo, totalFee, description, return_url, cancel_url)
}

func CaptureOrder(ctx context.Context, orderID string) (result string, err error) {
	return defsys.CaptureOrder(ctx, orderID)
}

func VerifyWebhook(headers map[string]string, body []byte) (bool, error) {
	return defsys.VerifyWebhook(headers, body)
}
