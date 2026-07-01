package bailian

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/aliyun/alibaba-cloud-sdk-go/sdk"
	"github.com/aliyun/alibaba-cloud-sdk-go/sdk/auth/credentials"
	"github.com/aliyun/alibaba-cloud-sdk-go/sdk/requests"
)

func newSys(options Options) (sys *Bailian, err error) {
	if options.AccessKeyId == "" || options.AccessKeySecret == "" {
		return nil, errors.New("bailian: AccessKeyId/AccessKeySecret is empty")
	}
	sys = &Bailian{options: options}
	c := sdk.NewConfig()
	c.HttpTransport = &http.Transport{}
	c.Timeout = options.Timeout
	cred := credentials.NewAccessKeyCredential(options.AccessKeyId, options.AccessKeySecret)
	sys.client, err = sdk.NewClientWithOptions(options.RegionId, c, cred)
	return
}

type Bailian struct {
	options Options
	client  *sdk.Client
}

// POP 的通用响应包装
type popResp struct {
	Code           string          `json:"Code"`
	HttpStatusCode int             `json:"HttpStatusCode"`
	Message        string          `json:"Message"`
	RequestId      string          `json:"RequestId"`
	Success        bool            `json:"Success"`
	Data           json.RawMessage `json:"Data"`
}

func (this *Bailian) call(apiName string, params map[string]string) (*Data, error) {
	req := requests.NewCommonRequest()
	req.Method = "POST"
	req.Scheme = "https"
	req.Domain = this.options.Endpoint
	req.Version = this.options.Version
	req.ApiName = apiName
	for k, v := range params {
		req.QueryParams[k] = v
	}
	rsp, err := this.client.ProcessCommonRequest(req)
	if err != nil {
		return nil, err
	}
	var pr popResp
	if err = json.Unmarshal(rsp.GetHttpContentBytes(), &pr); err != nil {
		return nil, err
	}
	if !pr.Success {
		return nil, &PopError{
			Code:       pr.Code,
			Message:    pr.Message,
			HttpStatus: pr.HttpStatusCode,
			RequestId:  pr.RequestId,
		}
	}
	data := &Data{}
	if len(pr.Data) > 0 {
		if err = json.Unmarshal(pr.Data, data); err != nil {
			return nil, err
		}
	}
	return data, nil
}

func (this *Bailian) DeviceRegister(req *DeviceRegisterReq) (*Data, error) {
	return this.call("DeviceRegister", map[string]string{
		"Nonce":       req.Nonce,
		"AppId":       req.AppId,
		"RequestTime": req.RequestTime,
		"Signature":   req.Signature,
	})
}

func (this *Bailian) GetToken(req *GetTokenReq) (*Data, error) {
	if this.options.ApiKey == "" {
		return nil, errors.New("bailian: ApiKey is empty, required for GetToken (tokenKey)")
	}
	return this.call("GetToken", map[string]string{
		"Nonce":       req.Nonce,
		"AppId":       req.AppId,
		"DeviceName":  req.DeviceName,
		"RequestTime": req.RequestTime,
		"Signature":   req.Signature,
		"TokenType":   req.TokenType,
		"TokenKey":    this.options.ApiKey,
	})
}
