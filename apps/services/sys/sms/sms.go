package sms

import (
	"strings"

	"github.com/tencentcloud/tencentcloud-sdk-go/tencentcloud/common"
	"github.com/tencentcloud/tencentcloud-sdk-go/tencentcloud/common/profile"
	sms "github.com/tencentcloud/tencentcloud-sdk-go/tencentcloud/sms/v20210111" // 引入sms
)

func newSys(options Options) (sys *SMS, err error) {
	sys = &SMS{options: options}
	// 必要步骤：
	// 实例化一个认证对象，入参需要传入腾讯云账户密钥对secretId，secretKey。
	credential := common.NewCredential(
		options.SecretId,  // 替换为你的SecretId
		options.SecretKey, // 替换为你的SecretKey
	)
	// 实例化一个客户端配置对象，可以指定超时时间等配置
	cpf := profile.NewClientProfile()
	cpf.HttpProfile.ReqMethod = "POST"
	cpf.HttpProfile.ReqTimeout = 30
	cpf.SignMethod = "HmacSHA1"
	// 实例化要请求产品的client对象
	sys.client, err = sms.NewClient(credential, "ap-guangzhou", cpf)
	return
}

type SMS struct {
	options Options
	client  *sms.Client
}

// 发送短信验证吗
func (this *SMS) SendCaptcha(mobile string, captcha string) (err error) {
	var (
		Template string
	)
	if strings.Contains(mobile, "+86") {
		Template = this.options.Template1
	} else {
		Template = this.options.Template2
	}

	// 实例化一个请求对象，根据调用的接口和实际情况，可以进一步设置请求参数
	request := sms.NewSendSmsRequest()
	// 基本类型的设置。
	request.SmsSdkAppId = common.StringPtr(this.options.AppId)      // 替换为你的SDK AppID
	request.SignName = common.StringPtr(this.options.SignName)      // 替换为你的签名
	request.TemplateId = common.StringPtr(Template)                 // 替换为你的模板ID
	request.PhoneNumberSet = common.StringPtrs([]string{mobile})    // 替换为接收短信的手机号
	request.TemplateParamSet = common.StringPtrs([]string{captcha}) // 替换为模板中的参数
	// 通过client对象调用想要访问的接口，需要传入请求对象
	if _, err = this.client.SendSms(request); err != nil {
		return
	}
	return
}
