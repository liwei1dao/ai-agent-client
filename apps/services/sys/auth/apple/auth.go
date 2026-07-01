package apple_auth

import (
	"context"
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"math/big"
	"net/http"
	"strings"

	"github.com/golang-jwt/jwt/v5"
)

type appleKey struct {
	Kty string `json:"kty"`
	Kid string `json:"kid"`
	Use string `json:"use"`
	Alg string `json:"alg"`
	N   string `json:"n"`
	E   string `json:"e"`
}
type appleKeyResponse struct {
	Keys []appleKey `json:"keys"`
}

func newSys(options Options) (sys *Google, err error) {
	sys = &Google{
		options: options,
	}

	return
}

type Google struct {
	options Options
}

func (this *Google) Auth(ctx context.Context, identityToken string) (info string, err error) {
	// 获取 token header 部分
	parts := strings.Split(identityToken, ".")
	if len(parts) < 2 {
		return "", errors.New("invalid token")
	}

	// 解码 header，提取 kid
	headerSegment, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return "", err
	}
	var header map[string]interface{}
	if err := json.Unmarshal(headerSegment, &header); err != nil {
		return "", err
	}
	kid := header["kid"].(string)

	// 获取 apple 公钥列表
	keys, err := fetchApplePublicKeys()
	if err != nil {
		return "", err
	}

	var pubKey *rsa.PublicKey
	for _, key := range keys {
		if key.Kid == kid {
			pubKey, err = buildRSAPublicKey(key.N, key.E)
			if err != nil {
				return "", err
			}
			break
		}
	}
	if pubKey == nil {
		return "", errors.New("public key not found")
	}

	// 验证 JWT
	token, err := jwt.Parse(identityToken, func(t *jwt.Token) (interface{}, error) {
		return pubKey, nil
	})
	if err != nil || !token.Valid {
		return "", errors.New("invalid token")
	}

	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok {
		return "", errors.New("invalid claims")
	}

	// 额外校验 iss/aud（推荐做）
	if claims["iss"] != "https://appleid.apple.com" {
		return "", errors.New("invalid issuer")
	}
	// 如果你知道前端用的 client_id，也可以校验 aud：
	// if claims["aud"] != "com.your.bundle.id" {
	//     return "", errors.New("invalid audience")
	// }

	sub := claims["sub"].(string) // Apple 的唯一用户 ID
	return sub, nil
}

// 获取 Apple 公钥列表
func fetchApplePublicKeys() ([]appleKey, error) {
	resp, err := http.Get("https://appleid.apple.com/auth/keys")
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	var keyResp appleKeyResponse
	if err := json.Unmarshal(body, &keyResp); err != nil {
		return nil, err
	}
	return keyResp.Keys, nil
}

// 将 base64 N 和 E 转换成 RSA 公钥
func buildRSAPublicKey(nStr, eStr string) (*rsa.PublicKey, error) {
	nBytes, err := base64.RawURLEncoding.DecodeString(nStr)
	if err != nil {
		return nil, err
	}
	eBytes, err := base64.RawURLEncoding.DecodeString(eStr)
	if err != nil {
		return nil, err
	}

	e := 0
	for _, b := range eBytes {
		e = e<<8 + int(b)
	}

	return &rsa.PublicKey{
		N: new(big.Int).SetBytes(nBytes),
		E: e,
	}, nil
}
