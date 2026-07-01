package ali_auth

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/aliyun/alibaba-cloud-sdk-go/sdk"
	"github.com/aliyun/alibaba-cloud-sdk-go/sdk/auth/credentials"
	"github.com/aliyun/alibaba-cloud-sdk-go/sdk/requests"
)

func newSys(options Options) (sys *AliYUn, err error) {
	sys = &AliYUn{options: options}
	c := sdk.NewConfig()
	c.HttpTransport = &http.Transport{
		IdleConnTimeout: time.Duration(10 * time.Second),
	}
	c.EnableAsync = true
	c.GoRoutinePoolSize = 1
	c.MaxTaskQueueSize = 1
	c.Timeout = 10 * time.Second
	credential := credentials.NewAccessKeyCredential(options.AccessKeyId, options.AccessKeySecret)
	sys.client, err = sdk.NewClientWithOptions("cn-shanghai", c, credential)
	return
}

type AliYUn struct {
	options Options
	client  *sdk.Client
}

func (this *AliYUn) GetAppkey() string {
	return this.options.Appkey
}
func (this *AliYUn) GetToken() (token string, err error) {
	request := requests.NewCommonRequest()
	request.Method = "POST"
	request.Domain = "nls-meta.cn-shanghai.aliyuncs.com"
	request.ApiName = "CreateToken"
	request.Version = "2019-02-28"
	response, err := this.client.ProcessCommonRequest(request)
	if err != nil {
		return
	}
	var tr TokenResult
	err = json.Unmarshal([]byte(response.GetHttpContentString()), &tr)
	if err == nil {
		token = tr.Token.Id
	}
	return
}
