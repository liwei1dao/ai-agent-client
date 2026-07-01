package cos_test

import (
	"context"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"
	lgcos "yunyan/sys/tencentyun/cos"

	"github.com/tencentyun/cos-go-sdk-v5"
	sts "github.com/tencentyun/qcloud-cos-sts-sdk/go"
)

func Test_Sys(t *testing.T) {
	if os.Getenv("TENCENT_SECRET_ID") == "" || os.Getenv("TENCENT_SECRET_KEY") == "" {
		t.Skip("TENCENT_SECRET_ID/TENCENT_SECRET_KEY env not set")
	}
	if err := lgcos.OnInit(nil,
		lgcos.SetSecretID(os.Getenv("TENCENT_SECRET_ID")),
		lgcos.SetSecretKey(os.Getenv("TENCENT_SECRET_KEY")),
		lgcos.SetAppId("1253517901"),
		lgcos.SetRegion("ap-guangzhou"),
		lgcos.SetBucketName("deepsound-1253517901"),
		lgcos.SetBucketURL("https://deepsound-1253517901.cos.ap-guangzhou.myqcloud.com"),
		lgcos.SetDomainName("app.deepsoud.com"),
	); err != nil {
		return
	} else {
		// var file *os.File
		// defer file.Close()
		// if file, err = os.Open("./DeapSound_0619.apk"); err != nil {
		// 	fmt.Println("打开文件失败!", err)
		// 	return
		// }
		results := lgcos.GetFileUrl("app/DeapSound_0619.apk")
		fmt.Printf("results:%s", results)
	}
}

func Test_Sys_Sts(t *testing.T) {
	if os.Getenv("TENCENT_SECRET_ID") == "" || os.Getenv("TENCENT_SECRET_KEY") == "" {
		t.Skip("TENCENT_SECRET_ID/TENCENT_SECRET_KEY env not set")
	}
	if err := lgcos.OnInit(nil,
		lgcos.SetSecretID(os.Getenv("TENCENT_SECRET_ID")),
		lgcos.SetSecretKey(os.Getenv("TENCENT_SECRET_KEY")),
		lgcos.SetAppId("1253517901"),
		lgcos.SetRegion("ap-guangzhou"),
		lgcos.SetBucketName("deepsound-1253517901"),
		lgcos.SetBucketURL("https://deepsound-1253517901.cos.ap-guangzhou.myqcloud.com"),
	); err != nil {
		return
	} else {
		results, err := lgcos.Sts()
		// fmt.Printf("TmpSecretId:%s TmpSecretKey:%s SessionToken:%s err:%v", results.Credentials.TmpSecretID, results.Credentials.TmpSecretKey, results.Credentials.SessionToken, err)

		// 你的 COS 存储桶信息
		bucketURL := "https://deepsound-1253517901.cos.ap-guangzhou.myqcloud.com"

		// 通过 STS 获取的临时凭证
		tmpSecretID := results.Credentials.TmpSecretID
		tmpSecretKey := results.Credentials.TmpSecretKey
		sessionToken := results.Credentials.SessionToken

		// 初始化 COS 客户端
		u, _ := url.Parse(bucketURL)
		b := &cos.BaseURL{BucketURL: u}

		client := cos.NewClient(b, &http.Client{
			Transport: &cos.AuthorizationTransport{
				SecretID:     tmpSecretID,
				SecretKey:    tmpSecretKey,
				SessionToken: sessionToken, // 关键部分，必须加上 SessionToken
			},
		})
		// objectKey := "test.txt"
		// content := "Hello, COS with STS!"
		// _, err = client.Object.Put(context.Background(), objectKey,
		// 	strings.NewReader(content), nil)
		// if err != nil {
		// 	log.Fatalf("上传对象失败: %v", err)
		// }
		// fmt.Printf("成功上传对象: %s\n", objectKey)

		// 测试下载对象
		// resp, err := client.Object.Get(context.Background(), objectKey, nil)
		// if err != nil {
		// 	log.Fatalf("下载对象失败: %v", err)
		// }
		// defer resp.Body.Close()
		// body, err := io.ReadAll(resp.Body)
		// if err != nil {
		// 	log.Fatalf("读取对象内容失败: %v", err)
		// }
		// fmt.Printf("下载对象内容: %s\n", string(body))
		// 示例：列出存储桶中的对象
		result, _, err := client.Bucket.Get(context.Background(), nil)
		if err != nil {
			fmt.Println("请求失败：", err)
			return
		}

		for _, v := range result.Contents {
			fmt.Println("文件名：", v.Key)
		}
	}
}

func Test_Sys_Sts1(t *testing.T) {
	// 替换为您的永久密钥
	secretID := os.Getenv("TENCENT_SECRET_ID")
	secretKey := os.Getenv("TENCENT_SECRET_KEY")
	if secretID == "" || secretKey == "" {
		t.Skip("TENCENT_SECRET_ID/TENCENT_SECRET_KEY env not set")
	}

	// 配置存储桶信息
	appID := "1253517901"
	bucket := "deepsound-1253517901"
	region := "ap-guangzhou"
	bucketURL := fmt.Sprintf("https://%s.cos.%s.myqcloud.com", bucket, region)

	// 创建 STS 客户端
	client := sts.NewClient(secretID, secretKey, nil)

	// 配置策略
	policy := &sts.CredentialPolicy{
		Version: "2.0",
		Statement: []sts.CredentialPolicyStatement{
			{
				Effect: "allow",
				Action: []string{
					"name/cos:GetObject",
					"name/cos:PutObject",
					"name/cos:ListBucket",
				},
				Resource: []string{
					fmt.Sprintf("qcs::cos:%s:uid/%s:%s", region, appID, bucket),
					fmt.Sprintf("qcs::cos:%s:uid/%s:%s/*", region, appID, bucket),
				},
			},
		},
	}

	// 配置临时密钥参数
	opt := &sts.CredentialOptions{
		DurationSeconds: int64(time.Hour.Seconds()), // 有效期：1小时
		Region:          region,
		Policy:          policy,
	}

	// 获取临时密钥
	result, err := client.GetCredential(opt)
	if err != nil {
		log.Fatalf("获取临时密钥失败: %v", err)
	}

	fmt.Printf("临时密钥信息：\n")
	fmt.Printf("TmpSecretId: %s\n", result.Credentials.TmpSecretID)
	fmt.Printf("TmpSecretKey: %s\n", result.Credentials.TmpSecretKey)
	fmt.Printf("SessionToken: %s\n", result.Credentials.SessionToken)
	fmt.Printf("开始时间: %d\n", result.StartTime)
	fmt.Printf("过期时间: %d\n", result.ExpiredTime)

	// 使用临时密钥配置 COS 客户端
	u, _ := url.Parse(bucketURL)
	b := &cos.BaseURL{BucketURL: u}
	cosClient := cos.NewClient(b, &http.Client{
		Transport: &cos.AuthorizationTransport{
			SecretID:     result.Credentials.TmpSecretID,
			SecretKey:    result.Credentials.TmpSecretKey,
			SessionToken: result.Credentials.SessionToken,
		},
	})

	// 测试上传对象
	objectKey := "test.txt"
	content := "Hello, COS with STS!"
	_, err = cosClient.Object.Put(context.Background(), objectKey,
		strings.NewReader(content), nil)
	if err != nil {
		log.Fatalf("上传对象失败: %v", err)
	}
	fmt.Printf("成功上传对象: %s\n", objectKey)

	// 测试下载对象
	resp, err := cosClient.Object.Get(context.Background(), objectKey, nil)
	if err != nil {
		log.Fatalf("下载对象失败: %v", err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		log.Fatalf("读取对象内容失败: %v", err)
	}
	fmt.Printf("下载对象内容: %s\n", string(body))
}
