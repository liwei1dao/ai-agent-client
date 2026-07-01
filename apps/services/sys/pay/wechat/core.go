package wechat

import "context"

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
	// WxPayTransaction 解密后的核心交易数据（Ciphertext 解密后得到的结构）
	WxPayTransaction struct {
		// 3.1 订单基础信息
		OutTradeNo     string `json:"out_trade_no"`     // 商户订单号（你下单时传入的 order_no）
		TransactionId  string `json:"transaction_id"`   // 微信支付订单号（微信生成的唯一订单ID）
		Mchid          string `json:"mchid"`            // 商户号（你的商户ID，如 1652202222）
		Appid          string `json:"appid"`            // 应用ID（你的 AppID，如 wx4b5ec8957ad5e425）
		TradeType      string `json:"trade_type"`       // 交易类型（App 支付固定为 "APP"）
		TradeState     string `json:"trade_state"`      // 支付状态（核心字段）
		TradeStateDesc string `json:"trade_state_desc"` // 支付状态描述（如 "支付成功"）

		// 3.2 金额信息
		Amount struct {
			Total         int64  `json:"total"`          // 订单总金额（单位：分，如 100 表示 1 元）
			PayerTotal    int64  `json:"payer_total"`    // 支付金额（用户实际支付的金额，通常与 total 一致）
			Currency      string `json:"currency"`       // 货币类型（默认 "CNY"，人民币）
			PayerCurrency string `json:"payer_currency"` // 用户支付的货币类型（默认 "CNY"）
		} `json:"amount"`

		// 3.3 支付者信息
		Payer struct {
			Openid string `json:"openid"` // 用户唯一标识（App 支付可不返回，JSAPI 支付必返）
		} `json:"payer"`

		// 3.4 时间信息
		SuccessTime string `json:"success_time"` // 支付成功时间（格式：yyyy-MM-dd'T'HH:mm:ss+TIMEZONE，仅支付成功时返回）
		CreateTime  string `json:"create_time"`  // 订单创建时间（格式同上）
		CloseTime   string `json:"close_time"`   // 订单关闭时间（仅订单关闭时返回，格式同上）

		// 3.5 附加信息
		Attach     string `json:"attach"`      // 附加数据（你下单时传入的 attach 字段，如 "test_attach"）
		NotifyUrl  string `json:"notify_url"`  // 回调通知地址（你下单时传入的 notify_url）
		NotifyTime string `json:"notify_time"` // 回调通知时间（格式同上）
		NotifyId   string `json:"notify_id"`   // 回调通知ID（微信生成的唯一标识）
	}

	ISys interface {
		GenerateOrderNo(prefix string) string
		CreateAppOrder(ctx context.Context, outTradeNo string, totalFee int64, description string, notifyurl string) (result *AppPayParams, err error)
		DecryptWxPayNotify(associatedData, nonce, ciphertext string) (*WxPayTransaction, error)
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

func CreateAppOrder(ctx context.Context, outTradeNo string, totalFee int64, description string, notifyurl string) (result *AppPayParams, err error) {
	return defsys.CreateAppOrder(ctx, outTradeNo, totalFee, description, notifyurl)
}

func DecryptWxPayNotify(associatedData, nonce, ciphertext string) (*WxPayTransaction, error) {
	return defsys.DecryptWxPayNotify(associatedData, nonce, ciphertext)
}
