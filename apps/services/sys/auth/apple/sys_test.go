package apple_auth_test

import (
	"context"
	"fmt"
	"os"
	"testing"
	apple_auth "yunyan/sys/auth/apple"
)

func Test_Sys_Chat(t *testing.T) {
	idToken := os.Getenv("APPLE_AUTH_ID_TOKEN")
	if idToken == "" {
		t.Skip("APPLE_AUTH_ID_TOKEN env not set")
	}
	if sys, err := apple_auth.NewSys(); err != nil {
		fmt.Printf("Sys Init err:%v", err)
	} else {
		info, err := sys.Auth(context.Background(), idToken)
		fmt.Printf("Sys info:%+v err:%v", info, err)
	}
}
