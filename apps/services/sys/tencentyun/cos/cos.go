package cos

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"time"

	"github.com/tencentyun/cos-go-sdk-v5"
	sts "github.com/tencentyun/qcloud-cos-sts-sdk/go"
)

func newSys(options Options) (sys *COS, err error) {
	sys = &COS{
		options: options,
	}
	bucketURL, _ := url.Parse(options.BucketURL)
	baseURL := &cos.BaseURL{BucketURL: bucketURL}
	// 创建客户端，使用永久密钥
	sys.client = cos.NewClient(baseURL, &http.Client{
		Transport: &cos.AuthorizationTransport{
			SecretID:  options.SecretID,  // 腾讯云密钥 SecretId
			SecretKey: options.SecretKey, // 腾讯云密钥 SecretKey
		},
	})
	return
}

type COS struct {
	options Options
	client  *cos.Client
}

// 临时访问
func (this *COS) Sts() (result *sts.CredentialResult, err error) {
	// STS 配置
	client := sts.NewClient(this.options.SecretID, this.options.SecretKey, nil)

	// 定义权限策略
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
					fmt.Sprintf("qcs::cos:%s:uid/%s:%s", this.options.Region, this.options.AppId, this.options.BucketName),
					fmt.Sprintf("qcs::cos:%s:uid/%s:%s/*", this.options.Region, this.options.AppId, this.options.BucketName),
				},
			},
		},
	}
	// 设置临时密钥参数
	opt := &sts.CredentialOptions{
		DurationSeconds: int64(time.Hour.Seconds()), // 有效期：1小时
		Region:          this.options.Region,        // 替换为你的存储桶所在地域
		Policy:          policy,
	}
	// 获取临时密钥
	result, err = client.GetCredential(opt)
	if err != nil {
		return
	}
	return
}

func (this *COS) Get(name string) (resp *cos.Response, err error) {
	resp, err = this.client.Object.Get(context.Background(), name, nil)
	return
}
func (this *COS) GetFileUrl(name string) (publicURL string) {
	if this.options.DomainName == "" {
		publicURL = fmt.Sprintf("https://%s.cos.%s.myqcloud.com/%s", this.options.BucketName, this.options.Region, name)
	} else {
		publicURL = fmt.Sprintf("https://%s/%s", this.options.DomainName, name)
	}

	return
}

func (this *COS) Put(name string, r io.Reader) (publicURL string, err error) {
	_, err = this.client.Object.Put(context.Background(), name, r, nil)
	if this.options.DomainName == "" {
		publicURL = fmt.Sprintf("https://%s.cos.%s.myqcloud.com/%s", this.options.BucketName, this.options.Region, name)
	} else {
		publicURL = fmt.Sprintf("https://%s/%s", this.options.DomainName, name)
	}
	return
}

func (this *COS) Delete(name string) (err error) {
	_, err = this.client.Object.Delete(context.Background(), name, nil)
	return
}
