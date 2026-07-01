package googleiap_test

import (
	"context"
	"os"
	"testing"
	"yunyan/sys/pay/googleiap"
)

func TestNewSys(t *testing.T) {
	saJSON := os.Getenv("GOOGLE_IAP_SA_JSON")
	purchaseToken := os.Getenv("GOOGLE_IAP_TEST_PURCHASE_TOKEN")
	if saJSON == "" || purchaseToken == "" {
		t.Skip("GOOGLE_IAP_* env not set")
	}
	sys, err := googleiap.NewSys(
		googleiap.SetServiceAccountJSON(saJSON),
	)
	if err != nil {
		t.Errorf("NewSys() error = %v", err)
		return
	}
	ok, err := sys.VerifyProductPurchase(context.Background(), "com.saitong.voitrans", "ai_001", purchaseToken)
	if err != nil {
		t.Errorf("VerifyProductPurchase() error = %v", err)
		return
	}
	if !ok {
		t.Errorf("VerifyProductPurchase() ok = %v", ok)
		return
	}
}
