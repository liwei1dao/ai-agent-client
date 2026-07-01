package tos_test

import (
	"context"
	"fmt"
	"os"
	"testing"
	"yunyan/lego/sys/sdk/bytedance/tos"
)

func Test_Sys(t *testing.T) {
	accessKey := os.Getenv("BYTEDANCE_TOS_ACCESS_KEY")
	secretKey := os.Getenv("BYTEDANCE_TOS_SECRET_KEY")
	if accessKey == "" || secretKey == "" {
		t.Skip("BYTEDANCE_TOS_ACCESS_KEY / BYTEDANCE_TOS_SECRET_KEY not set, skip")
	}
	if err := tos.OnInit(nil,
		tos.SetAsccessKey(accessKey),
		tos.SetSecretKey(secretKey),
		tos.SetRegion("cn-shanghai"),
		tos.SetBucketName("insightcube"),
	); err != nil {
		return
	} else {
		var file *os.File
		defer file.Close()
		if file, err = os.Open("./liwei.text"); err != nil {
			fmt.Println("打开文件失败!", err)
			return
		}
		err = tos.Put(context.Background(), "./liwei.text", file)
		fmt.Printf("results:%v", err)
	}
}
