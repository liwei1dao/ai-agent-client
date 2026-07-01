package wechat_test

import (
	"context"
	"fmt"
	"os"
	"testing"
	"yunyan/sys/pay/wechat"
)

func Test_Sys(t *testing.T) {
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
		fmt.Printf("Sys Init err:%v", err)
		return
	} else {
		orderid := sys.GenerateOrderNo("APP")
		fmt.Println(orderid)
		results, err := sys.CreateAppOrder(context.TODO(), orderid, 100, "vip购买", "https://api.ideapsound.com/api/heom/pay_wechatnotify")
		fmt.Println(results, err)
	}
}
