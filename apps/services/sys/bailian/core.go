package bailian

// 百炼多模态设备计量管理服务 —— 半托管模式
// 参考：https://help.aliyun.com/zh/model-studio/multimodal-interaction-license
// 本包封装 POP 网关的两个接口：DeviceRegister / GetToken
// 业务逻辑由 modules/bailian 透传给设备。

// 设备端上送的注册请求（原样转发给 POP）
type DeviceRegisterReq struct {
	AppId       string // 必填，产品标识
	Nonce       string // 必填，设备生成的 16 字节随机数（32 字符）
	RequestTime string // 必填，设备端毫秒时间戳字符串，5 分钟内有效
	Signature   string // 必填，设备 SDK 生成的签名
}

// 设备端上送的获取令牌请求（原样转发给 POP，tokenKey 由本包补注）
type GetTokenReq struct {
	AppId       string // 必填
	DeviceName  string // 必填，设备唯一标识
	Nonce       string // 必填
	RequestTime string // 必填
	Signature   string // 必填
	TokenType   string // 必填，当前仅 "MMI"
}

// POP 返回的 data 字段 —— 直接透传给设备端解签
type Data struct {
	Nonce        string `json:"nonce"`
	ResponseTime string `json:"responseTime"`
	AppId        string `json:"appId"`
	DeviceName   string `json:"deviceName,omitempty"`
	RequestIp    string `json:"requestIp,omitempty"`
	Signature    string `json:"signature"`
}

// POP 错误：业务可直接将 Code/Message 回给设备端
type PopError struct {
	Code       string
	Message    string
	HttpStatus int
	RequestId  string
}

func (e *PopError) Error() string {
	return e.Code + ": " + e.Message
}

type ISys interface {
	DeviceRegister(req *DeviceRegisterReq) (*Data, error)
	GetToken(req *GetTokenReq) (*Data, error)
}

var defsys ISys

func OnInit(config map[string]interface{}, option ...Option) (err error) {
	defsys, err = newSys(newOptions(config, option...))
	return
}

func NewSys(option ...Option) (sys ISys, err error) {
	sys, err = newSys(newOptionsByOption(option...))
	return
}

func DeviceRegister(req *DeviceRegisterReq) (*Data, error) { return defsys.DeviceRegister(req) }
func GetToken(req *GetTokenReq) (*Data, error)             { return defsys.GetToken(req) }
