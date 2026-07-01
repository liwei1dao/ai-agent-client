package alipay_test

import (
	"context"
	"fmt"
	"os"
	"testing"
	"yunyan/sys/pay/wechat"
)

// Test_Sys 使用微信支付系统对象创建订单的最小集成测试。
// 参数:
//   - t: Go 测试对象
//
// 返回值:
//   - 无
//
// 异常:
//   - 当未启用集成测试时跳过
//   - 当初始化或下单失败时，测试失败
func Test_Sys(t *testing.T) {
	if os.Getenv("WECHAT_PAY_INTEGRATION_TEST") == "" {
		t.Skip("跳过测试：未设置环境变量 WECHAT_PAY_INTEGRATION_TEST")
	}
	appID := os.Getenv("WECHAT_PAY_APP_ID")
	mchID := os.Getenv("WECHAT_PAY_MCH_ID")
	apiV3Key := os.Getenv("WECHAT_PAY_API_V3_KEY")
	privateKeyPath := os.Getenv("WECHAT_PAY_PRIVATE_KEY_PATH")
	certSerialNo := os.Getenv("WECHAT_PAY_CERT_SERIAL_NO")
	if appID == "" || mchID == "" || apiV3Key == "" || privateKeyPath == "" || certSerialNo == "" {
		t.Skip("WECHAT_PAY_* env not set")
	}
	if sys, err := wechat.NewSys(
		wechat.SetAppID(appID),
		wechat.SetMchID(mchID),
		wechat.SetApiV3Key(apiV3Key),
		wechat.SetPrivateKeyPath(privateKeyPath),
		wechat.SetCertSerialNo(certSerialNo),
	); err != nil {
		t.Fatalf("Sys Init err:%v", err)
	} else {
		orderid := sys.GenerateOrderNo("APP")
		fmt.Println(orderid)
		results, err := sys.CreateAppOrder(context.TODO(), orderid, 100, "vip购买", "https://api.ideapsound.com/api/heom/pay_wechatnotify")
		if err != nil {
			t.Fatalf("CreateAppOrder 失败: %v", err)
		}
		t.Logf("CreateAppOrder 成功: %+v", results)
	}
}
