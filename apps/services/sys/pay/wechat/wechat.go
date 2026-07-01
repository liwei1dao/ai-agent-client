package wechat

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"yunyan/lego/sys/log"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"math/rand"
	"time"

	"github.com/wechatpay-apiv3/wechatpay-go/core"
	"github.com/wechatpay-apiv3/wechatpay-go/core/option"
	"github.com/wechatpay-apiv3/wechatpay-go/services/payments/app"
	"github.com/wechatpay-apiv3/wechatpay-go/utils"
)

func newSys(options Options) (sys *WeChat, err error) {
	sys = &WeChat{
		options: options,
	}

	privateKey, err := utils.LoadPrivateKeyWithPath(options.PrivateKeyPath)
	if err != nil {
		log.Fatalf("加载商户私钥失败: %v", err)
	}

	// 2. 初始化客户端选项（推荐自动证书更新模式）
	ctx := context.Background()
	opts := []core.ClientOption{
		// 自动处理签名、验签，并定时更新微信支付平台证书
		option.WithWechatPayAutoAuthCipher(
			options.MchID,        // 商户号
			options.CertSerialNo, // 商户证书序列号
			privateKey,           // 商户私钥
			options.ApiV3Key,     // APIv3密钥（用于解密平台证书）
		),
	}

	// 3. 创建微信支付客户端
	sys.client, err = core.NewClient(ctx, opts...)
	if err != nil {
		log.Errorf("创建客户端失败: %v", err)
	}
	return
}

type WeChat struct {
	options Options
	client  *core.Client
}

// 生成商户订单号（示例：APP2024092515302234567890）
func (this *WeChat) GenerateOrderNo(prefix string) string {
	// 1. 时间戳：年月日时分秒（精确到秒，如 20240925153022）
	timeStr := time.Now().Format("20060102150405")

	// 2. 随机数：6位随机数字（避免同一秒内重复）
	rand.Seed(time.Now().UnixNano())      // 初始化随机数种子
	randNum := rand.Intn(900000) + 100000 // 生成 100000-999999 之间的随机数

	// 3. 拼接前缀（可选，用于区分业务类型，如 APP/JSAPI/NATIVE）
	return fmt.Sprintf("%s%s%d", prefix, timeStr, randNum)
}

// 创建App支付订单
func (this *WeChat) CreateAppOrder(ctx context.Context, outTradeNo string, totalFee int64, description string, notifyurl string) (result *AppPayParams, err error) {
	var (
		resp *app.PrepayWithRequestPaymentResponse
	)

	// 创建JSAPI支付服务
	svc := app.AppApiService{Client: this.client}

	// 构建创建订单请求参数
	req := app.PrepayRequest{
		Appid:       core.String(this.options.AppID), // 传入 AppID
		Mchid:       core.String(this.options.MchID),
		OutTradeNo:  core.String(outTradeNo),
		Description: core.String(description),
		Amount: &app.Amount{
			Total: core.Int64(totalFee),
		},
		NotifyUrl: core.String(notifyurl),
	}
	// 调用创建订单接口
	if resp, _, err = svc.PrepayWithRequestPayment(ctx, req); err != nil {
		err = fmt.Errorf("调用微信支付下单接口失败: %v", err)
		return
	}
	// 关键：JSAPI 支付的响应中有 Appid，无 PartnerId，签名字段是 PaySign
	result = &AppPayParams{
		AppID:     this.options.AppID, // 从配置取 AppID（响应中无此字段）
		PartnerID: *resp.PartnerId,    // 从响应取商户号（App 支付有此字段）
		PrepayID:  *resp.PrepayId,
		Package:   *resp.Package,
		NonceStr:  *resp.NonceStr,
		TimeStamp: *resp.TimeStamp,
		Sign:      *resp.Sign, // App 支付签名字段是 Sign
	}
	return
}

// DecryptWxPayNotify 解密微信支付回调的 ciphertext 字段
// 参数：
// - apiV3Key: 你的微信支付 APIv3 密钥（32位字符串）
// - associatedData: 回调中的 resource.associated_data
// - nonce: 回调中的 resource.nonce
// - ciphertext: 回调中的 resource.ciphertext（base64 编码）
// 返回：解密后的 WxPayTransaction 结构体
// DecryptWxPayNotify 修复后的解密函数
func (this *WeChat) DecryptWxPayNotify(associatedData, nonce, ciphertext string) (*WxPayTransaction, error) {
	// 1. 解码 base64 加密数据（ciphertext 解码后是「密文+Tag」）
	cipherBytes, err := base64.StdEncoding.DecodeString(ciphertext)
	if err != nil {
		return nil, fmt.Errorf("base64解码失败: %w", err)
	}

	// 2. 初始化 AES-GCM 解密器（APIv3 密钥作为密钥，此处无问题）
	block, err := aes.NewCipher([]byte(this.options.ApiV3Key))
	if err != nil {
		return nil, fmt.Errorf("初始化AES解密器失败: %w", err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("初始化GCM解密器失败: %w", err)
	}

	// 3. 关键修复：分离「密文」和「Tag」，并拼接成「密文+Tag」
	tagLength := 16
	if len(cipherBytes) < tagLength {
		return nil, fmt.Errorf("加密数据长度不足（需包含16字节Tag）")
	}
	actualCipherText := cipherBytes[:len(cipherBytes)-tagLength] // 实际密文
	tag := cipherBytes[len(cipherBytes)-tagLength:]              // 提取Tag
	combinedData := append(actualCipherText, tag...)             // 拼接「密文+Tag」（修复核心）

	// 4. 解密：传入拼接后的 combinedData（带Tag），而非单独的密文
	plaintextBytes, err := gcm.Open(
		nil,                    // 输出缓冲区（nil 表示自动分配）
		[]byte(nonce),          // 随机串（从回调获取，无问题）
		combinedData,           // 修复：用「密文+Tag」的组合
		[]byte(associatedData), // 附加数据（从回调获取，无问题）
	)
	if err != nil {
		return nil, fmt.Errorf("解密失败: %w", err)
	}

	// 5. 解析解密后的 JSON（无问题）
	var transaction WxPayTransaction
	if err := json.Unmarshal(plaintextBytes, &transaction); err != nil {
		return nil, fmt.Errorf("解析交易数据失败: %w", err)
	}

	return &transaction, nil
}
