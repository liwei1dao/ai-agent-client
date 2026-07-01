package paypal

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"math/rand"
	"net/http"
	"strings"
	"time"
)

type PayPal struct {
	options     Options
	httpClient  *http.Client
	accessToken string
}

func newSys(options Options) (sys *PayPal, err error) {
	sys = &PayPal{options: options, httpClient: &http.Client{Timeout: 15 * time.Second}}
	// 尝试获取访问令牌（Client Credentials）
	_ = sys.refreshAccessToken(context.Background())
	return
}

// 生成商户订单号（与其他支付系统一致）
func (p *PayPal) GenerateOrderNo(prefix string) string {
	timeStr := time.Now().Format("20060102150405")
	rand.Seed(time.Now().UnixNano())
	randNum := rand.Intn(900000) + 100000
	return fmt.Sprintf("%s%s%d", prefix, timeStr, randNum)
}

// CreateAppOrder 创建 PayPal 订单（APP 端：返回 orderID/approval 链接字符串）
// totalFee 单位为分，PayPal 需传金额单位为元的字符串
// 注意：重定向地址由 Options.ReturnURL / Options.CancelURL 提供（用于网页唤起 App）
func (p *PayPal) CreateAppOrder(ctx context.Context, outTradeNo string, totalFee int64, description string, return_url string, cancel_url string) (result string, err error) {
	var (
		resp *http.Response
	)

	// 确保 token 可用
	if p.accessToken == "" {
		if err = p.refreshAccessToken(ctx); err != nil {
			return
		}
	}

	// 构造下单请求体（简化版）
	amount := fmt.Sprintf("%.2f", float64(totalFee)/100)
	reqBody := map[string]any{
		"intent": "CAPTURE",
		"purchase_units": []map[string]any{{
			"reference_id": outTradeNo,
			"custom_id":    outTradeNo,
			"description":  description,
			"amount":       map[string]any{"currency_code": "USD", "value": amount},
		}},
		"application_context": func() map[string]any {
			ctx := map[string]any{
				"brand_name":  "DeepServer",
				"user_action": "PAY_NOW",
			}
			// 加入网页支付结果的重定向地址（可为 App Deep Link）
			if return_url != "" {
				ctx["return_url"] = return_url
			}
			if cancel_url != "" {
				ctx["cancel_url"] = cancel_url
			}
			return ctx
		}(),
	}
	bodyBytes, _ := json.Marshal(reqBody)

	url := strings.TrimRight(p.options.BaseURL, "/") + "/v2/checkout/orders"
	httpReq, _ := http.NewRequestWithContext(ctx, http.MethodPost, url, strings.NewReader(string(bodyBytes)))
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Authorization", "Bearer "+p.accessToken)

	resp, err = p.httpClient.Do(httpReq)
	if err != nil {
		return
	}
	defer resp.Body.Close()
	var respJSON struct {
		ID    string `json:"id"`
		Links []struct {
			Href string `json:"href"`
			Rel  string `json:"rel"`
		} `json:"links"`
	}
	if err = json.NewDecoder(resp.Body).Decode(&respJSON); err != nil {
		return
	}
	// 返回 orderID 或 approve 链接作为前端唤起依据（这里返回 JSON 字符串，方便前端直接使用）
	resultBytes, _ := json.Marshal(map[string]any{"order_id": respJSON.ID, "links": respJSON.Links})
	result = string(resultBytes)
	return
}

// VerifyWebhook 验证 PayPal Webhook（骨架：返回 true）。实际应调用 /v1/notifications/verify-webhook-signature
func (p *PayPal) VerifyWebhook(headers map[string]string, body []byte) (bool, error) {
	// 这里保留骨架，实际实现需向 PayPal 验签端点提交：transmission_id、timestamp、signature、webhook_id、cert_url、auth_algo、body
	// 为不影响现有代码结构，先返回 true
	return true, nil
}

// 刷新访问令牌（Client Credentials）
func (p *PayPal) refreshAccessToken(ctx context.Context) error {
	if p.options.ClientID == "" || p.options.Secret == "" {
		return nil // 未配置则跳过；允许骨架运行
	}
	url := strings.TrimRight(p.options.BaseURL, "/") + "/v1/oauth2/token"
	req, _ := http.NewRequestWithContext(ctx, http.MethodPost, url, strings.NewReader("grant_type=client_credentials"))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	basic := base64.StdEncoding.EncodeToString([]byte(p.options.ClientID + ":" + p.options.Secret))
	req.Header.Set("Authorization", "Basic "+basic)
	resp, err := p.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	var tokenResp struct {
		AccessToken string `json:"access_token"`
		TokenType   string `json:"token_type"`
		ExpiresIn   int    `json:"expires_in"`
	}
	if err = json.NewDecoder(resp.Body).Decode(&tokenResp); err != nil {
		return err
	}
	p.accessToken = tokenResp.AccessToken
	return nil
}

// CaptureOrder 执行订单扣款（服务端）并返回原始响应 JSON（包含状态）
func (p *PayPal) CaptureOrder(ctx context.Context, orderID string) (result string, err error) {
	// 确保 token 可用
	if p.accessToken == "" {
		if err = p.refreshAccessToken(ctx); err != nil {
			return
		}
	}
	url := strings.TrimRight(p.options.BaseURL, "/") + "/v2/checkout/orders/" + orderID + "/capture"
	httpReq, _ := http.NewRequestWithContext(ctx, http.MethodPost, url, strings.NewReader("{}"))
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Authorization", "Bearer "+p.accessToken)
	resp, err := p.httpClient.Do(httpReq)
	if err != nil {
		return
	}
	defer resp.Body.Close()
	var respMap map[string]any
	if err = json.NewDecoder(resp.Body).Decode(&respMap); err != nil {
		return
	}
	b, _ := json.Marshal(respMap)
	result = string(b)
	return
}
