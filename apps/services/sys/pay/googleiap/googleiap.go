package googleiap

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math/rand"
	"net/http"
	"os"
	"strings"
	"time"

	"golang.org/x/oauth2/google"
)

type googleIAP struct {
	opt   Options
	httpc *http.Client
}

func newSys(opt Options) (ISys, error) {
	return &googleIAP{
		opt:   opt,
		httpc: &http.Client{Timeout: 8 * time.Second},
	}, nil
}

// 生成商户订单号（与其他支付系统一致）
func (p *googleIAP) GenerateOrderNo(prefix string) string {
	timeStr := time.Now().Format("20060102150405")
	rand.Seed(time.Now().UnixNano())
	randNum := rand.Intn(900000) + 100000
	return fmt.Sprintf("%s%s%d", prefix, timeStr, randNum)
}

// VerifyProductPurchase 使用 Android Publisher API 校验一次性商品的购买
// GET https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{packageName}/purchases/products/{productId}/tokens/{token}
func (g *googleIAP) VerifyProductPurchase(ctx context.Context, packageName, productId, purchaseToken string) (bool, error) {
	if g.opt.Debug && g.opt.Log != nil {
		g.opt.Log.Infof("[GoogleIAP] verify product: pkg=%s product=%s token=%s", packageName, productId, maskToken(purchaseToken))
	}
	token, err := g.getAccessToken(ctx)
	if err != nil {
		return false, err
	}
	url := fmt.Sprintf("https://androidpublisher.googleapis.com/androidpublisher/v3/applications/%s/purchases/products/%s/tokens/%s", packageName, productId, purchaseToken)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return false, err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := g.httpc.Do(req)
	if err != nil {
		return false, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(resp.Body)
		msg := fmt.Sprintf("Google products 查询失败: %d %s", resp.StatusCode, string(b))
		if resp.StatusCode == http.StatusUnauthorized && strings.Contains(string(b), "permissionDenied") {
			msg = fmt.Sprintf("Google products 查询失败: 401 permissionDenied: 请在 Google Play Console 的 API 访问为服务账号授予对应用 %s 的权限", packageName)
		}
		return false, fmt.Errorf("%s", msg)
	}
	var out struct {
		PurchaseState    int64  `json:"purchaseState"`
		ConsumptionState int64  `json:"consumptionState"`
		DeveloperPayload string `json:"developerPayload"`
		// acknowledgementState 不总是出现在产品响应中
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return false, err
	}
	// 规则：purchaseState == 0 表示已购买；其余视为无效
	if out.PurchaseState != 0 {
		return false, fmt.Errorf("产品未处于购买状态: purchaseState=%d", out.PurchaseState)
	}
	return true, nil
}

// VerifySubscriptionPurchase 使用 Android Publisher API 校验订阅
// GET https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{packageName}/purchases/subscriptions/{subscriptionId}/tokens/{token}
func (g *googleIAP) VerifySubscriptionPurchase(ctx context.Context, packageName, subscriptionId, purchaseToken string) (bool, error) {
	if g.opt.Debug && g.opt.Log != nil {
		g.opt.Log.Infof("[GoogleIAP] verify subscription: pkg=%s sub=%s token=%s", packageName, subscriptionId, maskToken(purchaseToken))
	}
	token, err := g.getAccessToken(ctx)
	if err != nil {
		return false, err
	}
	url := fmt.Sprintf("https://androidpublisher.googleapis.com/androidpublisher/v3/applications/%s/purchases/subscriptions/%s/tokens/%s", packageName, subscriptionId, purchaseToken)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return false, err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := g.httpc.Do(req)
	if err != nil {
		return false, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(resp.Body)
		msg := fmt.Sprintf("Google subscriptions 查询失败: %d %s", resp.StatusCode, string(b))
		if resp.StatusCode == http.StatusUnauthorized && strings.Contains(string(b), "permissionDenied") {
			msg = fmt.Sprintf("Google subscriptions 查询失败: 401 permissionDenied: 请在 Google Play Console 的 API 访问为服务账号授予对应用 %s 的权限", packageName)
		}
		return false, fmt.Errorf("%s", msg)
	}
	var out struct {
		AcknowledgementState int64  `json:"acknowledgementState"`
		CancelReason         int64  `json:"cancelReason"`
		ExpiryTimeMillis     string `json:"expiryTimeMillis"`
		PaymentState         int64  `json:"paymentState"`
		// 其他字段：autoRenewing, kind 等
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return false, err
	}
	// 取消原因非 0 视为已取消
	if out.CancelReason != 0 {
		return false, fmt.Errorf("订阅已取消: cancelReason=%d", out.CancelReason)
	}
	// 检查过期时间
	if out.ExpiryTimeMillis != "" {
		// expiryTimeMillis 是毫秒字符串
		var ms int64
		_, err := fmt.Sscanf(out.ExpiryTimeMillis, "%d", &ms)
		if err == nil {
			if ms <= time.Now().UnixMilli() {
				return false, fmt.Errorf("订阅已过期: expiry=%s", out.ExpiryTimeMillis)
			}
		}
	}
	// 如果提供了 paymentState，则要求为 1（已支付）或 2（免费试用也可视为有效视业务而定）。此处要求至少为 1。
	if out.PaymentState != 0 && out.PaymentState < 1 {
		return false, fmt.Errorf("订阅支付状态异常: paymentState=%d", out.PaymentState)
	}
	return true, nil
}

func maskToken(t string) string {
	if len(t) <= 6 {
		return "***"
	}
	return fmt.Sprintf("%s***%s", t[:3], t[len(t)-3:])
}

// 获取 Android Publisher 访问令牌
func (g *googleIAP) getAccessToken(ctx context.Context) (string, error) {
	var jsonData []byte
	if g.opt.ServiceAccountJSON != "" {
		jsonData = []byte(g.opt.ServiceAccountJSON)
	} else if g.opt.ServiceAccountJSONPath != "" {
		b, err := os.ReadFile(g.opt.ServiceAccountJSONPath)
		if err != nil {
			return "", fmt.Errorf("读取服务账号文件失败: %w", err)
		}
		jsonData = b
	} else {
		return "", fmt.Errorf("未配置 ServiceAccountJSON 或 ServiceAccountJSONPath")
	}
	// 使用服务账号密钥创建 JWT 配置，Android Publisher scope
	config, err := google.JWTConfigFromJSON(jsonData, "https://www.googleapis.com/auth/androidpublisher")
	if err != nil {
		return "", fmt.Errorf("解析服务账号 JSON 失败: %w", err)
	}
	tok, err := config.TokenSource(ctx).Token()
	if err != nil {
		return "", fmt.Errorf("获取访问令牌失败: %w", err)
	}
	return tok.AccessToken, nil
}
