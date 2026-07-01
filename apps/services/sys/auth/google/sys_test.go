package google_auth_test

import (

	//"lego_bighealth/sys/coze"

	"context"
	"fmt"
	"os"
	"testing"
	google_auth "yunyan/sys/auth/google"
)

func Test_Sys_Chat(t *testing.T) {
	idToken := os.Getenv("GOOGLE_AUTH_ID_TOKEN")
	if idToken == "" {
		t.Skip("GOOGLE_AUTH_ID_TOKEN env not set")
	}
	if sys, err := google_auth.NewSys(); err != nil {
		fmt.Printf("Sys Init err:%v", err)
	} else {
		info, err := sys.Auth(context.Background(), idToken)
		fmt.Printf("Sys info:%+v err:%v", info, err)
	}
}
