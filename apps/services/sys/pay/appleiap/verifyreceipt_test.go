package appleiap_test

import (
	"context"
	"os"
	"strings"
	"testing"
	"time"

	"yunyan/sys/pay/appleiap"
)

func TestVerifyReceipt_JWSRoutesToTransaction(t *testing.T) {
	jws := os.Getenv("APPLE_IAP_TEST_JWS")
	if jws == "" {
		t.Skip("APPLE_IAP_TEST_JWS not set, skip")
	}
	sys, err := appleiap.NewSys(appleiap.SetUseSandbox(true))
	if err != nil {
		t.Fatalf("new sys err: %v", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	ok, err := sys.VerifyReceipt(ctx, jws)
	if err != nil {
		if !(strings.Contains(err.Error(), "缺少 App Store Server API 配置") || strings.Contains(err.Error(), "缺少 App Store bundleId") || strings.Contains(err.Error(), "Apple transactions 查询失败")) {
			t.Fatalf("unexpected error: %v", err)
		}
	} else {
		_ = ok
	}
}
