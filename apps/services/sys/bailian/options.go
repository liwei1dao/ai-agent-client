package bailian

import (
	"yunyan/lego/utils/mapstructure"
	"time"
)

type Option func(*Options)

type Options struct {
	RegionId        string        // 百炼区域，固定 cn-beijing
	Endpoint        string        // POP Endpoint: bailianmodelonchip.cn-beijing.aliyuncs.com
	Version         string        // API 版本: 2024-08-16
	AccessKeyId     string        // 阿里云主账号/RAM AK
	AccessKeySecret string        // 阿里云主账号/RAM AS
	ApiKey          string        // 百炼 API Key，仅 getToken 使用，不能下发给设备
	Timeout         time.Duration // 超时
}

func SetRegionId(v string) Option         { return func(o *Options) { o.RegionId = v } }
func SetEndpoint(v string) Option         { return func(o *Options) { o.Endpoint = v } }
func SetVersion(v string) Option          { return func(o *Options) { o.Version = v } }
func SetAccessKeyId(v string) Option      { return func(o *Options) { o.AccessKeyId = v } }
func SetAccessKeySecret(v string) Option  { return func(o *Options) { o.AccessKeySecret = v } }
func SetApiKey(v string) Option           { return func(o *Options) { o.ApiKey = v } }
func SetTimeout(v time.Duration) Option   { return func(o *Options) { o.Timeout = v } }

func newOptions(config map[string]interface{}, opts ...Option) Options {
	options := Options{
		RegionId: "cn-beijing",
		Endpoint: "bailianmodelonchip.cn-beijing.aliyuncs.com",
		Version:  "2024-08-16",
		Timeout:  10 * time.Second,
	}
	if config != nil {
		mapstructure.Decode(config, &options)
	}
	for _, o := range opts {
		o(&options)
	}
	return options
}

func newOptionsByOption(opts ...Option) Options {
	options := Options{
		RegionId: "cn-beijing",
		Endpoint: "bailianmodelonchip.cn-beijing.aliyuncs.com",
		Version:  "2024-08-16",
		Timeout:  10 * time.Second,
	}
	for _, o := range opts {
		o(&options)
	}
	return options
}
