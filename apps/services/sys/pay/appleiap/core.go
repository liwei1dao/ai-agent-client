package appleiap

import (
	"context"
)

type ISys interface {
	GenerateOrderNo(prefix string) string
	// VerifyReceipt 校验 base64 的收据（legacy verifyReceipt 或 App Store Server API）
	VerifyReceipt(ctx context.Context, receiptData string) (bool, error)
	// VerifyTransaction 校验交易 ID（使用 App Store Server API 查询）
	VerifyTransaction(ctx context.Context, transactionId string) (bool, error)
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

func GenerateOrderNo(prefix string) string {
	return defsys.GenerateOrderNo(prefix)
}

func VerifyReceipt(ctx context.Context, receiptData string) (bool, error) {
	return defsys.VerifyReceipt(ctx, receiptData)
}

func VerifyTransaction(ctx context.Context, transactionId string) (bool, error) {
	return defsys.VerifyTransaction(ctx, transactionId)
}
