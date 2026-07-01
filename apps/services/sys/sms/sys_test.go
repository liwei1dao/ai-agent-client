package sms_test

import (
	"fmt"
	"os"
	"testing"
	"yunyan/sys/sms"
)

// 国内
func Test_sys_china(t *testing.T) {
	if os.Getenv("TENCENT_SMS_SECRET_ID") == "" || os.Getenv("TENCENT_SMS_SECRET_KEY") == "" {
		t.Skip("TENCENT_SMS_SECRET_ID/TENCENT_SMS_SECRET_KEY env not set")
	}
	if sys, err := sms.NewSys(
		sms.SetAppId(os.Getenv("TENCENT_SMS_APP_ID")),
		sms.SetSecretId(os.Getenv("TENCENT_SMS_SECRET_ID")),
		sms.KeySecretKey(os.Getenv("TENCENT_SMS_SECRET_KEY")),
		sms.SetSignName(os.Getenv("TENCENT_SMS_SIGN_NAME")),
		sms.SetTemplate1(os.Getenv("TENCENT_SMS_TEMPLATE1")),
	); err == nil {
		err = sys.SendCaptcha("+8615336758045", "2341")
		fmt.Println(err)
	}
}

// 海外
func Test_sys_overseas(t *testing.T) {
	if os.Getenv("TENCENT_SMS_SECRET_ID_2") == "" || os.Getenv("TENCENT_SMS_SECRET_KEY_2") == "" {
		t.Skip("TENCENT_SMS_SECRET_ID_2/TENCENT_SMS_SECRET_KEY_2 env not set")
	}
	if sys, err := sms.NewSys(
		sms.SetAppId(os.Getenv("TENCENT_SMS_APP_ID_2")),
		sms.SetSecretId(os.Getenv("TENCENT_SMS_SECRET_ID_2")),
		sms.KeySecretKey(os.Getenv("TENCENT_SMS_SECRET_KEY_2")),
		sms.SetSignName(os.Getenv("TENCENT_SMS_SIGN_NAME_2")),
		sms.SetTemplate2(os.Getenv("TENCENT_SMS_TEMPLATE2")),
	); err == nil {
		err = sys.SendCaptcha("+85270278175", "2341")
		fmt.Println(err)
	}
}
