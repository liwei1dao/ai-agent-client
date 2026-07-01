package appleiap_test

import (
	"context"
	"os"
	"testing"
	"yunyan/sys/pay/appleiap"
)

func TestNewSys(t *testing.T) {
	bundleID := os.Getenv("APPLE_IAP_BUNDLE_ID")
	issuerID := os.Getenv("APPLE_IAP_ISSUER_ID")
	keyID := os.Getenv("APPLE_IAP_KEY_ID")
	privateKeyPEM := os.Getenv("APPLE_IAP_PRIVATE_KEY_PEM")
	jws := os.Getenv("APPLE_IAP_TEST_JWS")
	if bundleID == "" || issuerID == "" || keyID == "" || privateKeyPEM == "" || jws == "" {
		t.Skip("APPLE_IAP_* env not set")
	}
	sys, err := appleiap.NewSys(
		appleiap.SetAppStoreBundleID(bundleID),
		appleiap.SetAppStoreIssuerID(issuerID),
		appleiap.SetAppStoreKeyID(keyID),
		appleiap.SetAppStorePrivateKeyPEM(privateKeyPEM),
		appleiap.SetUseSandbox(true),
	)
	if err != nil {
		t.Errorf("NewSys() error = %v", err)
		return
	}

	ok, err := sys.VerifyReceipt(context.Background(), jws)
	if err != nil {
		t.Errorf("VerifyReceipt() error = %v", err)
		return
	}
	if !ok {
		t.Errorf("VerifyReceipt() ok = %v", ok)
		return
	}
}
