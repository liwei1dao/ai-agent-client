package api

import (
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v4"
)

// 需要记录操作日志的重要接口（增删改类操作）
var auditableAPIMap = map[string]bool{
	// 登录
	"api_login": false,
	// 管理员管理
	"api_addadminuser":    true,
	"api_deladminuser":    true,
	"api_updateadminuser": true,
	// 配置管理
	"api_addconfig":          true,
	"api_updateconfig":       true,
	"api_delconfig":          true,
	"api_addglobalconfigs":   true,
	"api_updateglobalconfig": true,
	"api_delglobalconfigs":   true,
	// 智能体
	"api_addagent":    true,
	"api_updateagent": true,
	"api_delagent":    true,
	// 产品管理
	"api_addproduct":        true,
	"api_updateproduct":     true,
	"api_delproduct":        true,
	"api_addproductversion": true,
	"api_delproductversion": true,
	// 工厂管理
	"api_addfactory":          true,
	"api_updatefactory":       true,
	"api_delfactory":          true,
	"api_createfactorydevics": true,
	"api_restfactorydevics":   true,
	"api_resetlicensestatus":  true,
	// 商品管理
	"api_addgoods":    true,
	"api_updategoods": true,
	"api_delgoods":    true,
	// 渠道包
	"api_addchannelapp":    true,
	"api_uploadchannelapp": true,
	"api_delchannelapp":    true,
	// MCP
	"api_addmcpservers":    true,
	"api_updatemcpservers": true,
	"api_delmcpservers":    true,
	// 模板
	"api_addtemplates":    true,
	"api_updatetemplates": true,
	"api_deltemplate":     true,
	// 唤醒词
	"api_addwakeupvoice":    true,
	"api_updatewakeupvoice": true,
	"api_delwakeupvoice":    true,
	// 用户管理
	"api_updateuser": true,
	// 邮件
	"api_sendsmtpemail": true,
	// 资源分发
	"api_dispatchresource":   true,
	"api_grantadminresource": true, // 超管→后台账号 资源点赠送
	// 统计
	"api_rebuildstats": true, // 全量重建统计
}

// 设置跨域
func cors() gin.HandlerFunc {
	return func(c *gin.Context) {
		method := c.Request.Method
		origin := c.Request.Header.Get("Origin")
		if origin != "" {
			c.Header("Access-Control-Allow-Origin", "*") // 可将将 * 替换为指定的域名
			c.Header("Access-Control-Allow-Methods", "POST, GET, OPTIONS, PUT, DELETE, UPDATE")
			c.Header("Access-Control-Allow-Headers", "Origin, X-Requested-With, Content-Type, Accept, Authorization")
			c.Header("Access-Control-Expose-Headers", "Content-Length, Access-Control-Allow-Origin, Access-Control-Allow-Headers, Cache-Control, Content-Language, Content-Type")
			c.Header("Access-Control-Allow-Credentials", "true")
		}
		if method == "OPTIONS" {
			c.AbortWithStatus(http.StatusNoContent)
		}
		c.Next()
	}
}

func parseToken(tokenString string, secretKey []byte) (*jwt.RegisteredClaims, error) {
	parsedToken, err := jwt.ParseWithClaims(tokenString, &jwt.RegisteredClaims{}, func(token *jwt.Token) (interface{}, error) {
		// Ensure the token method conforms to "SigningMethodHMAC"
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		return secretKey, nil
	})
	if err != nil {
		return nil, err
	}

	// Validate the token and extract the claims
	if claims, ok := parsedToken.Claims.(*jwt.RegisteredClaims); ok && parsedToken.Valid {
		return claims, nil
	} else {
		return nil, fmt.Errorf("invalid token")
	}
}

// 基准日期
var baseDate = time.Date(2025, 1, 1, 0, 0, 0, 0, time.UTC)

// createCode 将三个整数拼接成一个15位的十五进制字符串
func createCode(devicetype int, factoryid int, timeday int, number int) string {
	// 转换并格式化channel为4位十五进制
	deviceTsype := formatToHex(devicetype, 1)
	// 转换并格式化group为4位十五进制
	factoryId := formatToHex(factoryid, 2)
	// 转换并格式化number为7位十五进制
	timeDay := formatToHex(timeday, 4)
	// 转换并格式化number为7位十五进制
	numBer := formatToHex(number, 4)
	return deviceTsype + factoryId + timeDay + numBer
}

// GenerateCustomMAC 生成自定义MAC地址（4+8+16+20位分配）
// devicetype: 设备类型 (0-15, 4位)
// factoryid: 厂家ID (0-255, 8位)
// batchNumber: 批次数据 (如1.2版本号，直接存储，0-65535, 16位)
// serial: 生产编号 (0-1048575, 20位)
func GenerateCustomMAC(productid uint16, batchNumber byte, serial uint32) (code string, err error) {
	// 参数验证
	if productid > 0xFFFF {
		err = fmt.Errorf("productid must be <= 0xFFFF (16 bits)")
		return
	}
	if batchNumber > 0xFF {
		err = fmt.Errorf("batchNumber must be <= 0xFF (8 bits)")
		return
	}
	if serial > 0xFFFFFF {
		err = fmt.Errorf("serial must be <= 0xFFFFFF (24 bits)")
		return
	}

	mac := make([]byte, 6)

	// 第一个字节：productid的高8位
	mac[0] = byte((productid >> 8) & 0xFF)

	// 第二个字节：productid的低8位
	mac[1] = byte(productid & 0xFF)

	// 第三个字节：批次数据（1个字节）
	mac[2] = byte(batchNumber & 0xFF)

	// 第四个字节：生产编号的高8位
	mac[3] = byte((serial >> 16) & 0xFF)

	// 第五个字节：生产编号的中间8位
	mac[4] = byte((serial >> 8) & 0xFF)

	// 第六个字节：生产编号的低8位
	mac[5] = byte(serial & 0xFF)

	// 生成MAC地址字符串
	code = fmt.Sprintf("%02X:%02X:%02X:%02X:%02X:%02X", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5])
	return
}

// ParseCustomMAC 解析自定义MAC地址并提取原始数据
// 返回: productid, batchNumber, serial, error
func ParseCustomMAC(macCode string) (productid uint16, batchNumber byte, serial uint32, err error) {
	// 验证MAC地址格式（12个十六进制字符）
	if len(macCode) != 17 { // 包含冒号的格式如 AA:BB:CC:DD:EE:FF
		// 尝试解析没有冒号的格式
		if len(macCode) != 12 {
			err = fmt.Errorf("MAC地址长度错误，期望12字符或17字符(带冒号)，实际%d字符", len(macCode))
			return
		}
	} else {
		// 移除冒号
		macCode = strings.ReplaceAll(macCode, ":", "")
	}

	// 检查是否为有效的十六进制字符
	for i, char := range macCode {
		if !((char >= '0' && char <= '9') || (char >= 'A' && char <= 'F') || (char >= 'a' && char <= 'f')) {
			err = fmt.Errorf("第%d位包含无效字符: %c", i+1, char)
			return
		}
	}

	// 解析MAC地址的6个字节
	mac := make([]byte, 6)
	for i := 0; i < 6; i++ {
		value, parseErr := strconv.ParseUint(macCode[i*2:i*2+2], 16, 8)
		if parseErr != nil {
			err = fmt.Errorf("解析第%d字节失败: %v", i+1, parseErr)
			return
		}
		mac[i] = byte(value)
	}

	// 提取productid（第一个字节 + 第二个字节）
	productid = (uint16(mac[0]) << 8) | uint16(mac[1])

	// 提取批次数据（第三个字节）
	batchNumber = byte(mac[2])

	// 提取生产编号（第四个字节 + 第五个字节 + 第六个字节）
	serial = (uint32(mac[3]) << 16) | (uint32(mac[4]) << 8) | uint32(mac[5])

	return
}

// ConvertRelativeDaysToDate 将相对天数转换回实际日期
func ConvertRelativeDaysToDate(relativeDays uint16) uint32 {
	baseDate := uint32(20250101)
	baseYear := baseDate / 10000
	baseMonth := (baseDate % 10000) / 100
	baseDay := baseDate % 100

	// 简化计算：假设每月30天
	totalDays := baseYear*365 + baseMonth*30 + baseDay + uint32(relativeDays)

	// 转换回年月日格式（简化版本）
	year := totalDays / 365
	remainingDays := totalDays % 365
	month := remainingDays / 30
	day := remainingDays % 30

	if month == 0 {
		month = 1
	}
	if day == 0 {
		day = 1
	}

	return year*10000 + month*100 + day
}

// formatToHex 将整数转换为指定长度的十六进制字符串
func formatToHex(num, length int) string {
	if num < 0 {
		num = 0 // 处理负数情况
	}

	// 使用标准库转换为十六进制
	hexStr := fmt.Sprintf("%x", num)

	// 补零至指定长度
	hexStr = strings.ToUpper(fmt.Sprintf("%0*s", length, hexStr))

	// 截取指定长度（处理溢出情况）
	if len(hexStr) > length {
		hexStr = hexStr[len(hexStr)-length:]
	}

	return hexStr
}
