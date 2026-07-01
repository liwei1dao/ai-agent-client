package firebase_auth_test

import (

	//"lego_bighealth/sys/coze"

	"context"
	"fmt"
	"os"
	"testing"
	firebase_auth "yunyan/sys/auth/firebase"
)

func Test_Sys_Chat(t *testing.T) {
	idToken := os.Getenv("FIREBASE_AUTH_ID_TOKEN")
	if idToken == "" {
		t.Skip("FIREBASE_AUTH_ID_TOKEN env not set")
	}
	if sys, err := firebase_auth.NewSys(); err != nil {
		fmt.Printf("Sys Init err:%v", err)
	} else {
		info, err := sys.Auth(context.Background(), idToken)
		fmt.Printf("Sys info:%+v err:%v", info, err)
	}
}
