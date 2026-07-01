package googleiap

import (
	"context"
)

type ISys interface {
	GenerateOrderNo(prefix string) string
	// VerifyProductPurchase 校验一次性商品（in-app product）的购买凭证
	VerifyProductPurchase(ctx context.Context, packageName, productId, purchaseToken string) (bool, error)
	// VerifySubscriptionPurchase 校验订阅商品的购买凭证
	VerifySubscriptionPurchase(ctx context.Context, packageName, subscriptionId, purchaseToken string) (bool, error)
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
func VerifyProductPurchase(ctx context.Context, packageName, productId, purchaseToken string) (bool, error) {

	return defsys.VerifyProductPurchase(ctx, packageName, productId, purchaseToken)
}

func VerifySubscriptionPurchase(ctx context.Context, packageName, subscriptionId, purchaseToken string) (bool, error) {
	return defsys.VerifySubscriptionPurchase(ctx, packageName, subscriptionId, purchaseToken)
}
