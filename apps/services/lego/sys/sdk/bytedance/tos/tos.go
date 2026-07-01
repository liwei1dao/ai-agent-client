package tos

import (
	"context"
	"io"

	"github.com/volcengine/ve-tos-golang-sdk/v2/tos"
)

func newSys(options Options) (sys *TOS, err error) {
	sys = &TOS{
		options: options,
	}
	sys.client, err = tos.NewClientV2(options.Endpoint, tos.WithRegion(options.Region),
		tos.WithCredentials(tos.NewStaticCredentials(options.AsccessKey, options.SecretKey)))
	return
}

type TOS struct {
	options Options
	client  *tos.ClientV2
}

func (this *TOS) Get(ctx context.Context, name string, listener tos.DataTransferListener) (resp *tos.GetObjectV2Output, err error) {
	// 下载数据到内存
	resp, err = this.client.GetObjectV2(ctx, &tos.GetObjectV2Input{
		Bucket: this.options.BucketName,
		Key:    name,
		// 获取当前下载进度
		DataTransferListener: listener,
		// 下载时重写响应头
		ResponseContentType: "application/json",
	})
	return
}

func (this *TOS) Put(ctx context.Context, name string, r io.Reader) (err error) {
	_, err = this.client.PutObjectV2(ctx, &tos.PutObjectV2Input{
		PutObjectBasicInput: tos.PutObjectBasicInput{
			Bucket: this.options.BucketName,
			Key:    name,
		},
		Content: r,
	})
	return
}
