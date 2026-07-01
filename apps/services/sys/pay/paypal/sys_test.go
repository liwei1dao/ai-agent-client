package paypal_test

import (
	"context"
	"fmt"
	"os"
	"testing"
	"yunyan/sys/pay/paypal"
)

func Test_Sys(t *testing.T) {
	clientID := os.Getenv("PAYPAL_CLIENT_ID")
	secret := os.Getenv("PAYPAL_CLIENT_SECRET")
	if clientID == "" || secret == "" {
		t.Skip("PAYPAL_CLIENT_ID/PAYPAL_CLIENT_SECRET env not set")
	}
	if sys, err := paypal.NewSys(
		paypal.SetClientID(clientID),
		paypal.SetSecret(secret),
		// PayPal 正确的 Sandbox API 域名应为 api-m.sandbox.paypal.com
		paypal.SetBaseURL("https://api-m.sandbox.paypal.com"),
		paypal.SetWebhookID("0PR35225Y36017238"),
		paypal.SetDebug(true),
	); err != nil {
		fmt.Printf("Sys Init err:%v", err)
		return
	} else {
		orderid := sys.GenerateOrderNo("APP")
		fmt.Println(orderid)
		results, err := sys.CreateAppOrder(context.TODO(), orderid, 100, "Sandbox测试购买", "", "")
		fmt.Println(results, err)
	}
}

func Test_Sys_CaptureOrder(t *testing.T) {
	clientID := os.Getenv("PAYPAL_CLIENT_ID")
	secret := os.Getenv("PAYPAL_CLIENT_SECRET")
	if clientID == "" || secret == "" {
		t.Skip("PAYPAL_CLIENT_ID/PAYPAL_CLIENT_SECRET env not set")
	}
	if sys, err := paypal.NewSys(
		paypal.SetClientID(clientID),
		paypal.SetSecret(secret),
		// PayPal 正确的 Sandbox API 域名应为 api-m.sandbox.paypal.com
		paypal.SetBaseURL("https://api-m.sandbox.paypal.com"),
		paypal.SetWebhookID("0PR35225Y36017238"),
		paypal.SetDebug(true),
	); err != nil {
		fmt.Printf("Sys Init err:%v", err)
		return
	} else {
		results, err := sys.CaptureOrder(context.TODO(), "1A196717NX085042G")
		fmt.Println(results, err)
	}
}
