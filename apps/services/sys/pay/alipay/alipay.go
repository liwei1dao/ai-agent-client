package alipay

import (
	"context"
	"fmt"
	"math/rand"
	"net/url"
	"time"

	"github.com/smartwalle/alipay/v3"
)

func newSys(options Options) (sys *Alipay, err error) {
	sys = &Alipay{
		options: options,
	}
	// 初始化支付宝客户端
	if sys.client, err = alipay.New(options.AppID, options.PrivateKey, false); err != nil {
		return
	}
	// 加载支付宝公钥（用于验证回调）
	if err = sys.client.LoadAliPayPublicKey(options.PublicKey); err != nil {
		return
	}
	return
}

type Alipay struct {
	options Options
	client  *alipay.Client
}

// 生成商户订单号（示例：APP2024092515302234567890）
func (this *Alipay) GenerateOrderNo(prefix string) string {
	// 1. 时间戳：年月日时分秒（精确到秒，如 20240925153022）
	timeStr := time.Now().Format("20060102150405")

	// 2. 随机数：6位随机数字（避免同一秒内重复）
	rand.Seed(time.Now().UnixNano())      // 初始化随机数种子
	randNum := rand.Intn(900000) + 100000 // 生成 100000-999999 之间的随机数

	// 3. 拼接前缀（可选，用于区分业务类型，如 APP/JSAPI/NATIVE）
	return fmt.Sprintf("%s%s%d", prefix, timeStr, randNum)
}

// 创建App支付订单
func (this *Alipay) CreateAppOrder(ctx context.Context, outTradeNo string, totalFee int64, description string, notifyurl string) (result string, err error) {

	// 构建支付宝订单请求
	var p = alipay.TradeAppPay{}
	p.OutTradeNo = outTradeNo                                  // 商户订单号
	p.TotalAmount = fmt.Sprintf("%.2f", float64(totalFee)/100) // 金额（单位元，保留两位小数）
	p.Subject = description                                    // 订单标题
	p.ProductCode = "QUICK_MSECURITY_PAY"                      // 固定值
	p.NotifyURL = notifyurl                                    // 异步通知地址

	// 生成支付参数（字符串形式，用于前端调起支付宝）
	result, err = this.client.TradeAppPay(p)
	if err != nil {
		return
	}
	return
}

// 验证订单
func (this *Alipay) DecryptWxPayNotify(values url.Values) (ok bool, err error) {
	// 验证回调签名（确保是支付宝官方发送的通知）
	if err = this.client.VerifySign(values); err != nil {
		return
	}
	ok = true
	return
}
