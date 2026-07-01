package sts_test

import (
	"fmt"
	"testing"

	"yunyan/sys/aliyun/sts"
)

//   oss: #对象存储（真实凭据请从环境变量注入，参见 .env.example）
//     Endpoint: https://oss-ap-southeast-1.aliyuncs.com
//     AccessKeyId: <ALIYUN_ACCESS_KEY_ID>
//     AccessKeySecret: <ALIYUN_ACCESS_KEY_SECRET>
//     BucketName: dpmobj

func Test_STS(t *testing.T) {
	sys, err := sts.NewSys(
		sts.SetRegionId("cn-shenzhen"),
		sts.SetAccessKeyId("xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"),
		sts.SetAccessKeySecret("xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"),
	)
	if err != nil {
		fmt.Printf("初始化OSS 系统失败 err:%v", err)
		return
	} else {
		fmt.Printf("初始化OSS 系统成功")
		auth, err := sys.AssumeRole("xxxxxxxxxxxxxxxxxxxxxxxxxxx", "SessionTest")
		fmt.Printf("初始化OSS AssumeRole auth:%+v err:%v", auth, err)
	}
}
