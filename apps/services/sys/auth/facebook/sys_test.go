package facebook_auth_test

import (

	//"lego_bighealth/sys/coze"

	"context"
	"fmt"
	"os"
	"testing"
	facebook_auth "yunyan/sys/auth/facebook"
)

func Test_Sys(t *testing.T) {
	appID := os.Getenv("FACEBOOK_AUTH_APP_ID")
	appSecret := os.Getenv("FACEBOOK_APP_SECRET")
	idToken := os.Getenv("FACEBOOK_AUTH_ID_TOKEN")
	if appID == "" || appSecret == "" || idToken == "" {
		t.Skip("FACEBOOK_AUTH_APP_ID/FACEBOOK_APP_SECRET/FACEBOOK_AUTH_ID_TOKEN env not set")
	}
	if sys, err := facebook_auth.NewSys(
		facebook_auth.SetAppID(appID),
		facebook_auth.SetAppSecret(appSecret),
	); err != nil {
		fmt.Printf("Sys Init err:%v", err)
	} else {
		info, err := sys.Auth(context.Background(), idToken)
		fmt.Printf("info:%v err:%v", info, err)
	}
}
