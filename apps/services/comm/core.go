package comm

import (
	"context"
	cryptorand "crypto/rand"
	"yunyan/lego/base"
	"yunyan/lego/core"
	"yunyan/pb"
	"errors"
	"fmt"
	"math/rand"
	"reflect"
	"strconv"
)

type IService interface {
	base.IRPCXService
	GetUserSession(ctx context.Context, mate map[string]string) (session IUserSession)
	PutUserSession(session IUserSession)
}

// ApiInterceptor API 请求拦截器函数
// 在 handler 执行前调用，返回 *pb.ErrorData 表示拦截（不继续执行handler），返回 nil 表示放行
type ApiInterceptor func(apiName string, session IUserSession, msg interface{}) *pb.ErrorData

// ApiAuditFunc API 请求审计回调函数
// apiName: 接口名称, session: 用户会话, reqBody: 请求体, respBody: 响应体, code: 状态码, costMs: 耗时(毫秒)
type ApiAuditFunc func(apiName string, session IUserSession, reqBody []byte, respBody []byte, code int32, costMs int64)

type ISC_HttpRouteComp interface {
	core.IServiceComp
	Rpc_GatewayHttpRoute(ctx context.Context, args *pb.Rpc_GatewayHttpRouteReq, reply *pb.Rpc_GatewayHttpRouteResp) error
	//注册路由
	RegisterRoute(methodName string, isEncrypt bool, comp reflect.Value, msg reflect.Type, handle reflect.Method)
	AddInterceptor(interceptor ApiInterceptor) // 添加 API 请求拦截器
	AddApiAuditHook(hook ApiAuditFunc)         // 添加 API 审计回调钩子
}

// 用户会话
type IUserSession interface {
	context.Context
	SetSession(ctx context.Context, mate map[string]string)
	GetMateToString(key string) string
	GetMateToInt64(key string) int64
	GetMateToUInt64(key string) uint64
	GetMateToInt32(key string) int32
	GetMateToFloat64(key string) float64
	SetMateForFloat64(key string, value float64)
	SetMateForInt64(key string, value int64)
	GetMateToBool(key string) bool
	GetIP() string
	GetUserId() string
	Reset()
	SetMate(name string, value string)
	SetMates(meta map[string]string)
	GetMate(name string) (value string, ok bool)
	SetCache(name string, value interface{})
	GetCache(name string) (value interface{}, ok bool)
	Clone() (session IUserSession) //克隆
	GetMetas() (meta map[string]string)
}

type HttpResult struct {
	// 错误代码
	// @Description 响应结果的错误码 0 表示成功
	// @example 0
	Code pb.ErrorCode `json:"code" example:"0" description:"请求回应Code 0表示成功 非0 请求异常"`
	// 消息说明
	// @Description 响应结果的消息 请求返回的描述信息
	// @example "Success"
	Message string `json:"msg" example:"Success" description:"code 对应的描述信息"`
	// 数据部分，可能是多种类型
	// @Description 响应的数据，类型可变
	// @oneOf User Product Order
	// @example {"id": 1, "name": "John Doe"}
	Data interface{} `json:"data" description:"返回的数据对象"`
}

// ai 工具结构
type IAITool struct {
}

const (
	totalSegments = 5 // 5段，每段4字符 = 20字符 = 10字节
	segmentLength = 4
)

// GenerateLicense 生成授权码（10字节版本，20位序列号）
// productid: 产品ID (0-65535, 16位)
// batchNumber: 批次数据 (0-255, 8位)
// serialNumber: 设备编号 (0-1048575, 20位)
func GenerateLicense(productid uint16, batchNumber byte, serialNumber uint32) (string, error) {
	// 参数验证
	if productid > 0xFFFF {
		return "", errors.New("产品ID必须在0-65535之间")
	}
	if batchNumber < 1 || batchNumber > 255 {
		return "", errors.New("批次数据必须在1-255之间")
	}
	if serialNumber > 0xFFFFF {
		return "", errors.New("设备编号必须在0-1048575之间（20位）")
	}

	// 生成随机种子（2字节）
	seedBytes := make([]byte, 2)
	if _, err := cryptorand.Read(seedBytes); err != nil {
		return "", fmt.Errorf("生成随机种子失败: %v", err)
	}
	seed := int(seedBytes[0])<<8 | int(seedBytes[1])
	seedSegment := fmt.Sprintf("%04X", seed)

	// 使用种子初始化随机数生成器
	rng := rand.New(rand.NewSource(int64(seed)))

	// 生成4段混淆数据（每段2字节）
	confusionData := make([]int, 4)
	for i := 0; i < 4; i++ {
		confusionData[i] = rng.Intn(65536) // 0-65535
	}

	// 数据分配（总共44位有效数据）：
	// 产品ID: 16位
	// 批次数据: 8位
	// 序列号: 20位
	// 总计: 44位，分布在64位（4段×16位）中

	// 第1段：产品ID的高8位 + 产品ID的低8位
	data1 := int(productid)
	confusionData[0] ^= data1

	// 第2段：批次数据(8位) + 序列号的高8位
	data2 := (int(batchNumber) << 8) | (int(serialNumber>>12) & 0xFF)
	confusionData[1] ^= data2

	// 第3段：序列号的中间12位
	data3 := (int(serialNumber>>0) & 0xFFF)
	confusionData[2] ^= data3

	// 第4段：16位随机填充
	confusionData[3] ^= rng.Intn(65536)

	// 构建授权码（5段，共20字符）
	segments := make([]string, 5)
	segments[0] = seedSegment
	for i := 1; i < 5; i++ {
		segments[i] = fmt.Sprintf("%04X", confusionData[i-1])
	}

	// 组合成最终格式
	licenseCode := ""
	for _, segment := range segments {
		licenseCode += segment
	}

	return licenseCode, nil
}

// GeneratePublicCode 生成厂家公码（6 位短码，字符集去除易混的 0/O/I/1）
// 用于厂家公码场景：人眼可读、可手抄/可打印
func GeneratePublicCode() (string, error) {
	const charset = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // 32 字符
	const length = 6
	buf := make([]byte, length)
	rb := make([]byte, length)
	if _, err := cryptorand.Read(rb); err != nil {
		return "", fmt.Errorf("生成公码失败: %v", err)
	}
	for i := 0; i < length; i++ {
		buf[i] = charset[int(rb[i])%len(charset)]
	}
	return string(buf), nil
}

// ValidateLicense 验证授权码并提取数据（10字节版本，20位序列号）
// 返回: productid, batchNumber, serialNumber, error
func ValidateLicense(licenseCode string) (productid uint16, batchNumber byte, serialNumber uint32, err error) {
	// 检查总长度（5段 * 4字符 = 20字符）
	expectedLength := 5 * 4
	if len(licenseCode) != expectedLength {
		return 0, 0, 0, fmt.Errorf("授权码长度错误，期望%d字符，实际%d字符", expectedLength, len(licenseCode))
	}

	// 按固定长度分割
	segments := make([]string, 5)
	for i := 0; i < 5; i++ {
		start := i * 4
		end := start + 4
		segments[i] = licenseCode[start:end]
	}

	// 检查每段是否为有效的十六进制字符
	for i, segment := range segments {
		for _, char := range segment {
			if !((char >= '0' && char <= '9') || (char >= 'A' && char <= 'F') || (char >= 'a' && char <= 'f')) {
				return 0, 0, 0, fmt.Errorf("第%d段包含无效字符: %c", i+1, char)
			}
		}
	}

	// 解析种子
	seed, err := strconv.ParseInt(segments[0], 16, 32)
	if err != nil {
		return 0, 0, 0, errors.New("无效的种子段")
	}

	// 使用相同的种子重新生成随机数序列
	rng := rand.New(rand.NewSource(seed))

	// 解析混淆数据段
	confusionData := make([]int, 4)
	for i := 1; i < 5; i++ {
		value, err := strconv.ParseInt(segments[i], 16, 32)
		if err != nil {
			return 0, 0, 0, fmt.Errorf("无效的数据段 %d", i)
		}
		confusionData[i-1] = int(value)
	}

	// 重新生成原始混淆数据
	originalConfusion := make([]int, 4)
	for i := 0; i < 4; i++ {
		originalConfusion[i] = rng.Intn(65536)
	}

	// 通过异或运算恢复真实数据
	data1 := confusionData[0] ^ originalConfusion[0]
	productid = uint16(data1 & 0xFFFF)

	// 恢复批次数据和序列号高8位
	data2 := confusionData[1] ^ originalConfusion[1]
	batchNumber = byte((data2 >> 8) & 0xFF)
	serialNumberHigh := uint32(data2&0xFF) << 12

	// 恢复序列号的中间12位
	data3 := confusionData[2] ^ originalConfusion[2]
	serialNumberMid := uint32(data3 & 0xFFF)

	// 组合20位序列号
	serialNumber = serialNumberHigh | serialNumberMid

	// // 验证数据范围
	if batchNumber < 1 || batchNumber > 255 {
		return 0, 0, 0, errors.New("批次数据异常")
	}
	if serialNumber > 0xFFFFF {
		return 0, 0, 0, errors.New("设备编号数据异常")
	}

	return productid, batchNumber, serialNumber, nil
}
