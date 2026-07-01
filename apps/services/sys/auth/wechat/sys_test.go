package wechat_auth_test

import (
	"context"
	"fmt"
	"os"
	"testing"
	wechat_auth "yunyan/sys/auth/wechat"
)

func Test_Sys_Chat(t *testing.T) {
	appID := os.Getenv("WECHAT_AUTH_APP_ID")
	appSecret := os.Getenv("WECHAT_AUTH_APP_SECRET")
	code := os.Getenv("WECHAT_AUTH_CODE")
	if appID == "" || appSecret == "" || code == "" {
		t.Skip("WECHAT_AUTH_APP_ID/WECHAT_AUTH_APP_SECRET/WECHAT_AUTH_CODE env not set")
	}
	if sys, err := wechat_auth.NewSys(
		wechat_auth.SetAppID(appID),
		wechat_auth.SetAppSecret(appSecret),
	); err != nil {
		fmt.Printf("Sys Init err:%v", err)
	} else {
		info, err := sys.Auth(context.Background(), code)
		fmt.Printf("Sys info:%+v err:%v", info, err)
	}
}
