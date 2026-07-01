package appleiap

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"math/rand"
	"net/http"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

type appleIAP struct {
	opt   Options
	httpc *http.Client
}

func newSys(opt Options) (ISys, error) {
	return &appleIAP{
		opt:   opt,
		httpc: &http.Client{Timeout: 8 * time.Second},
	}, nil
}

// 生成商户订单号（与其他支付系统一致）
func (this *appleIAP) GenerateOrderNo(prefix string) string {
	timeStr := time.Now().Format("20060102150405")
	rand.Seed(time.Now().UnixNano())
	randNum := rand.Intn(900000) + 100000
	return fmt.Sprintf("%s%s%d", prefix, timeStr, randNum)
}

// VerifyReceipt 骨架实现：直接返回 true。
// 可接入 legacy verifyReceipt：
// POST https://buy.itunes.apple.com/verifyReceipt 或 sandbox 验证地址
// 也可迁移到 App Store Server API，推荐优先使用新接口。
func (this *appleIAP) VerifyReceipt(ctx context.Context, receiptData string) (bool, error) {
	if this.opt.Debug && this.opt.Log != nil {
		this.opt.Log.Infof("[AppleIAP] verify receipt: sandbox=%v data=%s", this.opt.UseSandbox, mask(receiptData))
	}
	rd := strings.TrimSpace(receiptData)
	{
		parts := strings.Split(rd, ".")
		if len(parts) == 3 {
			payload, err := base64.RawURLEncoding.DecodeString(parts[1])
			if err == nil {
				var j map[string]any
				if json.Unmarshal(payload, &j) == nil {
					if txid, ok := j["transactionId"].(string); ok && txid != "" {
						return this.VerifyTransaction(ctx, txid)
					}
				}
			}
		}
	}
	if strings.HasPrefix(rd, "{") && strings.HasSuffix(rd, "}") {
		var tmp map[string]any
		if json.Unmarshal([]byte(rd), &tmp) == nil {
			if v, ok := tmp["receipt-data"].(string); ok && strings.TrimSpace(v) != "" {
				rd = strings.TrimSpace(v)
			} else if v, ok := tmp["latest_receipt"].(string); ok && strings.TrimSpace(v) != "" {
				rd = strings.TrimSpace(v)
			}
		}
	}
	if _, err := base64.StdEncoding.DecodeString(rd); err != nil {
		return false, fmt.Errorf("apple verifyReceipt failed, status=21002: invalid receipt-data base64")
	}
	receiptData = rd
	// Apple legacy verifyReceipt endpoints
	const prodURL = "https://buy.itunes.apple.com/verifyReceipt"
	const sandboxURL = "https://sandbox.itunes.apple.com/verifyReceipt"

	// Build request body
	body := map[string]any{
		"receipt-data":             receiptData,
		"exclude-old-transactions": true,
	}
	if this.opt.SharedSecret != "" {
		body["password"] = this.opt.SharedSecret
	}

	// Helper to POST and parse status
	post := func(url string) (int64, map[string]any, error) {
		data, _ := json.Marshal(body)
		req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(data))
		if err != nil {
			return 0, nil, err
		}
		req.Header.Set("Content-Type", "application/json")
		resp, err := this.httpc.Do(req)
		if err != nil {
			return 0, nil, err
		}
		defer resp.Body.Close()
		b, err := io.ReadAll(resp.Body)
		if err != nil {
			return 0, nil, err
		}
		var out map[string]any
		if err = json.Unmarshal(b, &out); err != nil {
			return 0, nil, err
		}
		// status 0 success; 21007 sandbox receipt sent to production
		var status int64
		if v, ok := out["status"].(float64); ok {
			status = int64(v)
		}
		return status, out, nil
	}

	// Decide initial endpoint
	url := prodURL
	if this.opt.UseSandbox {
		url = sandboxURL
	}
	status, _, err := post(url)
	if err != nil {
		return false, err
	}

	// Auto fallback on 21007 when hitting production with sandbox receipt
	if status == 21007 && url == prodURL {
		status, _, err = post(sandboxURL)
		if err != nil {
			return false, err
		}
	}
	// Success only when status == 0
	if status != 0 {
		return false, fmt.Errorf("apple verifyReceipt failed, status=%d: %s", status, statusMessage(status))
	}
	return true, nil
}

// VerifyTransaction 骨架实现：直接返回 true。
// 可接入 App Store Server API：
// GET https://api.appstoreconnect.apple.com/inApps/v1/transactions/{transactionId}
func (this *appleIAP) VerifyTransaction(ctx context.Context, transactionId string) (bool, error) {
	if this.opt.Debug && this.opt.Log != nil {
		this.opt.Log.Infof("[AppleIAP] verify tx: sandbox=%v txid=%s", this.opt.UseSandbox, mask(transactionId))
	}
	// Require App Store Server API credentials
	if this.opt.AppStoreIssuerID == "" || this.opt.AppStoreKeyID == "" || this.opt.AppStorePrivateKeyPEM == "" {
		return false, fmt.Errorf("缺少 App Store Server API 配置: 需 IssuerID, KeyID, PrivateKeyPEM")
	}
	// StoreKit inApps 必须在 JWT 载荷中携带 bid（bundleId）以通过授权
	if this.opt.AppStoreBundleID == "" {
		return false, fmt.Errorf("缺少 App Store bundleId: 请在 Options.AppStoreBundleID 设置目标应用的 bundleId")
	}

	// Build ES256 JWT for App Store Server API
	privKey, err := jwt.ParseECPrivateKeyFromPEM([]byte(this.opt.AppStorePrivateKeyPEM))
	if err != nil {
		return false, fmt.Errorf("解析私钥失败: %w", err)
	}

	claims := jwt.MapClaims{
		"iss": this.opt.AppStoreIssuerID,
		"iat": time.Now().Unix(),
		// App Store Connect / StoreKit 要求 token 生命周期 ≤ 20 分钟
		"exp": time.Now().Add(20 * time.Minute).Unix(),
		"aud": "appstoreconnect-v1",
		"bid": this.opt.AppStoreBundleID,
	}
	token := jwt.NewWithClaims(jwt.SigningMethodES256, claims)
	token.Header["kid"] = this.opt.AppStoreKeyID
	token.Header["typ"] = "JWT"

	signedJWT, err := token.SignedString(privKey)
	if err != nil {
		return false, fmt.Errorf("签名 JWT 失败: %w", err)
	}

	base := "https://api.storekit.itunes.apple.com/inApps/v1/transactions/"
	if this.opt.UseSandbox {
		base = "https://api.storekit-sandbox.itunes.apple.com/inApps/v1/transactions/"
	}
	url := base + transactionId

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return false, err
	}
	req.Header.Set("Authorization", "Bearer "+signedJWT)

	resp, err := this.httpc.Do(req)
	if err != nil {
		return false, err
	}
	defer resp.Body.Close()

	// 200 认为有效；其余状态视为失败
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(resp.Body)
		return false, fmt.Errorf("Apple transactions 查询失败: %d %s", resp.StatusCode, string(b))
	}

	// 响应包含 JWS；解析 payload 并进行基本一致性校验
	var out struct {
		SignedTransactionInfo string `json:"signedTransactionInfo"`
		// 可能存在 signedRenewalInfo 等字段，这里无需使用
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return false, err
	}
	if out.SignedTransactionInfo == "" {
		return false, fmt.Errorf("Apple 返回缺少 signedTransactionInfo")
	}
	parts := strings.Split(out.SignedTransactionInfo, ".")
	if len(parts) != 3 {
		return false, fmt.Errorf("Apple 返回的 signedTransactionInfo 非法")
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return false, fmt.Errorf("解析 Apple signedTransactionInfo 失败: %v", err)
	}
	var info struct {
		BundleID      string `json:"bundleId"`
		TransactionID string `json:"transactionId"`
		Environment   string `json:"environment"`
	}
	if err := json.Unmarshal(payload, &info); err != nil {
		return false, fmt.Errorf("解析 Apple 交易载荷失败: %v", err)
	}
	if info.BundleID == "" || !strings.EqualFold(info.BundleID, this.opt.AppStoreBundleID) {
		return false, fmt.Errorf("交易归属的 bundleId 不匹配: %s != %s", info.BundleID, this.opt.AppStoreBundleID)
	}
	if info.TransactionID == "" || info.TransactionID != transactionId {
		return false, fmt.Errorf("返回的 transactionId 不一致: %s != %s", info.TransactionID, transactionId)
	}
	if this.opt.UseSandbox {
		if !strings.EqualFold(info.Environment, "Sandbox") {
			return false, fmt.Errorf("交易环境不匹配(期望Sandbox): %s", info.Environment)
		}
	} else {
		if strings.EqualFold(info.Environment, "Sandbox") {
			return false, fmt.Errorf("交易环境不匹配(期望Production): %s", info.Environment)
		}
	}
	return true, nil
}

func mask(s string) string {
	if len(s) <= 6 {
		return "***"
	}
	return fmt.Sprintf("%s***%s", s[:3], s[len(s)-3:])
}

func statusMessage(code int64) string {
	switch code {
	case 0:
		return "OK"
	case 21000:
		return "Bad JSON"
	case 21001:
		return "App Store unavailable"
	case 21002:
		return "Malformed or missing receipt-data"
	case 21003:
		return "Receipt cannot be authenticated"
	case 21004:
		return "Shared secret mismatch"
	case 21005:
		return "Server unavailable, try again"
	case 21006:
		return "Subscription expired"
	case 21007:
		return "Sandbox receipt sent to production"
	case 21008:
		return "Production receipt sent to sandbox"
	default:
		return "Unknown error"
	}
}
