package appleiap_test

import (
	"context"
	"crypto/elliptic"
	"encoding/base64"
	"encoding/json"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// TestServerAPICredentials 生成 ES256 JWT 并请求 Apple Server API 一个无害端点，
// 以判断凭据是否“可用”（不校验具体交易）。
// 环境变量：
// - APPLE_ISSUER_ID
// - APPLE_KEY_ID
// - APPLE_PRIVATE_KEY_PEM  (完整 .p8 内容)
// - APPLE_USE_SANDBOX      (可选，"true" 走沙盒)
// 若缺少必要变量则跳过测试。
func TestServerAPICredentials(t *testing.T) {
	// Issuer ID / Key ID 来自环境变量，缺失则跳过
	iss := os.Getenv("APPLE_IAP_ISSUER_ID")
	kid := os.Getenv("APPLE_IAP_KEY_ID")
	if iss == "" || kid == "" {
		t.Skip("APPLE_IAP_ISSUER_ID / APPLE_IAP_KEY_ID not set, skip")
	}
	// StoreKit 要求 JWT 载荷包含 bid（bundleId），与交易所属 App 一致（公开标识）
	bundleID := os.Getenv("APPLE_IAP_BUNDLE_ID")
	if bundleID == "" {
		bundleID = "com.saitong.voitrans"
	}

	// 方式A：把 .p8 全文放到环境变量 APPLE_IAP_PRIVATE_KEY_PEM（包含完整头尾与换行）
	pem := os.Getenv("APPLE_IAP_PRIVATE_KEY_PEM")

	// 方式B：从常见本地路径读取（AuthKey_<KEYID>.p8 已被 .gitignore 排除，不入库）
	var usedPath string
	if pem == "" {
		candidates := []string{
			"./AuthKey_" + kid + ".p8",
			"./sys/pay/appleiap/AuthKey_" + kid + ".p8",
		}
		for _, p := range candidates {
			if _, err := os.Stat(p); err == nil {
				b, err := os.ReadFile(p)
				if err != nil {
					t.Fatalf("读取私钥文件失败(%s): %v", p, err)
				}
				pem = string(b)
				usedPath = p
				break
			}
		}
		if pem == "" {
			t.Skip("未找到 .p8 私钥（设置 APPLE_IAP_PRIVATE_KEY_PEM 或放置 AuthKey_" + kid + ".p8），skip")
		}
		t.Logf("使用密钥文件: %s", usedPath)
	}

	if iss == "" || kid == "" || pem == "" {
		t.Fatalf("缺少 Issuer/KeyID 或 .p8 内容为空")
	}

	priv, err := jwt.ParseECPrivateKeyFromPEM([]byte(pem))
	if err != nil {
		t.Fatalf("解析私钥失败: %v", err)
	}

	claims := jwt.MapClaims{
		"iss": iss,
		"iat": time.Now().Unix(),
		// App Store Connect 要求 token 生命周期 ≤ 20 分钟
		"exp": time.Now().Add(20 * time.Minute).Unix(),
		"aud": "appstoreconnect-v1",
		"bid": bundleID,
	}
	token := jwt.NewWithClaims(jwt.SigningMethodES256, claims)
	token.Header["kid"] = kid
	token.Header["typ"] = "JWT"
	signed, err := token.SignedString(priv)
	if err != nil {
		t.Fatalf("签名 JWT 失败: %v", err)
	}

	// 输出 JWT 头和载荷，便于排查 kid/aud/时间戳等问题
	{
		parts := strings.Split(signed, ".")
		if len(parts) == 3 {
			decode := func(s string) string {
				b, _ := base64.RawURLEncoding.DecodeString(s)
				return string(b)
			}
			t.Logf("JWT header: %s", decode(parts[0]))
			t.Logf("JWT payload: %s", decode(parts[1]))
			t.Logf("iat=%d exp=%d ttl=%ds now=%d", claims["iat"], claims["exp"], claims["exp"].(int64)-claims["iat"].(int64), time.Now().Unix())
			// 打印密钥曲线类型，必须为 P-256
			if priv != nil && priv.PublicKey.Curve == elliptic.P256() {
				t.Logf("EC 曲线: P-256")
			} else {
				t.Logf("EC 曲线: 非 P-256，可能导致验签失败")
			}
		}
	}

	// 使用同一 JWT 请求 App Store Connect API 进行对照（验证 JWT 是否被接受）
	{
		ctx2, cancel2 := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel2()
		req2, _ := http.NewRequestWithContext(ctx2, http.MethodGet, "https://api.appstoreconnect.apple.com/v1/apps?limit=1", nil)
		req2.Header.Set("Authorization", "Bearer "+signed)
		resp2, err2 := (&http.Client{Timeout: 10 * time.Second}).Do(req2)
		if err2 != nil {
			t.Logf("App Store Connect 请求错误: %v", err2)
		} else {
			defer resp2.Body.Close()
			body2, _ := io.ReadAll(resp2.Body)
			t.Logf("App Store Connect 状态码: %d", resp2.StatusCode)
			t.Logf("App Store Connect 响应体: %s", string(body2))
		}
	}

	// 查询 In-App Purchase 商品信息（按 productId 过滤）
	{
		// 尝试使用短 productId 以及带 bundleId 的完整 productId 两种形式
		// prod1 := "ai_001"
		prod2 := bundleID + ".ai_001"

		q := func(pid string) {
			ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
			defer cancel()
			u := "https://api.appstoreconnect.apple.com/v1/inAppPurchases?limit=5&filter[productId]=" + url.QueryEscape(pid)
			req, _ := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
			req.Header.Set("Authorization", "Bearer "+signed)
			resp, err := (&http.Client{Timeout: 10 * time.Second}).Do(req)
			if err != nil {
				t.Logf("[ASC] inAppPurchases(productId=%s) 请求错误: %v", pid, err)
				return
			}
			defer resp.Body.Close()
			b, _ := io.ReadAll(resp.Body)
			t.Logf("[ASC] inAppPurchases(productId=%s) 状态码: %d", pid, resp.StatusCode)
			t.Logf("[ASC] inAppPurchases(productId=%s) 响应体: %s", pid, string(b))
		}
		// q(prod1)
		q(prod2)
	}

	// 进一步：按 bundleId 找到 appId，再用 appId 查询该应用的 IAP 列表
	{
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		u := "https://api.appstoreconnect.apple.com/v1/apps?limit=2&filter[bundleId]=" + url.QueryEscape(bundleID)
		req, _ := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
		req.Header.Set("Authorization", "Bearer "+signed)
		resp, err := (&http.Client{Timeout: 10 * time.Second}).Do(req)
		if err != nil {
			t.Logf("[ASC] apps(filter[bundleId]) 请求错误: %v", err)
		} else {
			defer resp.Body.Close()
			b, _ := io.ReadAll(resp.Body)
			t.Logf("[ASC] apps(filter[bundleId]) 状态码: %d", resp.StatusCode)
			t.Logf("[ASC] apps(filter[bundleId]) 响应体: %s", string(b))
			// 解析 appId
			var app struct {
				Data []struct {
					Id string `json:"id"`
				} `json:"data"`
			}
			if err := json.Unmarshal(b, &app); err == nil && len(app.Data) > 0 {
				appId := app.Data[0].Id
				ctx2, cancel2 := context.WithTimeout(context.Background(), 10*time.Second)
				defer cancel2()
				u2 := "https://api.appstoreconnect.apple.com/v1/apps/" + url.PathEscape(appId) + "/inAppPurchases?limit=5"
				req2, _ := http.NewRequestWithContext(ctx2, http.MethodGet, u2, nil)
				req2.Header.Set("Authorization", "Bearer "+signed)
				resp2, err2 := (&http.Client{Timeout: 10 * time.Second}).Do(req2)
				if err2 != nil {
					t.Logf("[ASC] apps/%s/inAppPurchases 请求错误: %v", appId, err2)
				} else {
					defer resp2.Body.Close()
					b2, _ := io.ReadAll(resp2.Body)
					t.Logf("[ASC] apps/%s/inAppPurchases 状态码: %d", appId, resp2.StatusCode)
					t.Logf("[ASC] apps/%s/inAppPurchases 响应体: %s", appId, string(b2))
				}
			}
		}
	}

	// 尝试个人密钥载荷（sub=user），以区分密钥类型导致的 401
	{
		now := time.Now().Unix()
		claims2 := jwt.MapClaims{
			"sub": "user",
			"aud": "appstoreconnect-v1",
			"iat": now,
			// 个人密钥同样遵循 ≤ 20 分钟的生命周期
			"exp": now + 1200,
			"bid": bundleID,
		}
		token2 := jwt.NewWithClaims(jwt.SigningMethodES256, claims2)
		token2.Header["kid"] = kid
		token2.Header["typ"] = "JWT"
		signed2, err := token2.SignedString(priv)
		if err != nil {
			t.Fatalf("签名 JWT(个人密钥载荷) 失败: %v", err)
		}

		parts := strings.Split(signed2, ".")
		if len(parts) == 3 {
			decode := func(s string) string {
				b, _ := base64.RawURLEncoding.DecodeString(s)
				return string(b)
			}
			t.Logf("[Individual] JWT header: %s", decode(parts[0]))
			t.Logf("[Individual] JWT payload: %s", decode(parts[1]))
			t.Logf("[Individual] iat=%d exp=%d ttl=%ds now=%d", claims2["iat"], claims2["exp"], claims2["exp"].(int64)-claims2["iat"].(int64), time.Now().Unix())
		}

		ctx3, cancel3 := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel3()
		req3, _ := http.NewRequestWithContext(ctx3, http.MethodGet, "https://api.appstoreconnect.apple.com/v1/apps?limit=1", nil)
		req3.Header.Set("Authorization", "Bearer "+signed2)
		resp3, err3 := (&http.Client{Timeout: 10 * time.Second}).Do(req3)
		if err3 != nil {
			t.Logf("[Individual] App Store Connect 请求错误: %v", err3)
		} else {
			defer resp3.Body.Close()
			body3, _ := io.ReadAll(resp3.Body)
			t.Logf("[Individual] App Store Connect 状态码: %d", resp3.StatusCode)
			t.Logf("[Individual] App Store Connect 响应体: %s", string(body3))
		}
	}

	base := "https://api.storekit.itunes.apple.com/inApps/v1/transactions/"
	// 如需沙箱测试，将 useSandbox 改为 true
	useSandbox := false
	if useSandbox {
		base = "https://api.storekit-sandbox.itunes.apple.com/inApps/v1/transactions/"
	}
	// 使用一个明显不存在的 transactionId，预期返回 404 或 400；401/403 则代表凭据不可用
	url := base + "invalid-test-txid"

	req, err := http.NewRequestWithContext(context.Background(), http.MethodGet, url, nil)
	if err != nil {
		t.Fatalf("构造请求失败: %v", err)
	}
	req.Header.Set("Authorization", "Bearer "+signed)

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		t.Fatalf("请求失败: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusUnauthorized || resp.StatusCode == http.StatusForbidden {
		// 输出更多错误信息便于定位（如 audience、kid、时间戳问题）
		b, _ := io.ReadAll(resp.Body)
		t.Fatalf("凭据不可用，状态码=%d，响应=%s；iss=%s kid=%s sandbox=%v", resp.StatusCode, string(b), iss, kid, useSandbox)
	}
	// 其他返回（如 404/400/200）均代表签名通过，凭据可用
}
