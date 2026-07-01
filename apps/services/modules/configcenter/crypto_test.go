package configcenter

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/sha256"
	"encoding/base64"
	"os"
	"testing"
)

// 用「文档里写给客户端的步骤」反向解密，验证服务端加密可被正确还原。
// 这段解密逻辑即客户端（Dart）需要复刻的算法参照。
func decryptRef(secret string, encoded string) ([]byte, error) {
	key := sha256.Sum256([]byte(secret))
	raw, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil {
		return nil, err
	}
	block, _ := aes.NewCipher(key[:])
	gcm, _ := cipher.NewGCM(block)
	ns := gcm.NonceSize() // 12
	nonce, ct := raw[:ns], raw[ns:]
	return gcm.Open(nil, nonce, ct, nil)
}

func TestEncryptRoundTrip(t *testing.T) {
	const secret = "unit-test-secret-key"
	os.Setenv("CC_TEST_KEY", secret)

	plain := []byte(`{"services":[{"id":"volc_llm"}],"globals":{"a":"b"}}`)
	enc, err := encryptJSON("CC_TEST_KEY", plain)
	if err != nil {
		t.Fatalf("encrypt: %v", err)
	}
	got, err := decryptRef(secret, enc)
	if err != nil {
		t.Fatalf("decrypt: %v", err)
	}
	if string(got) != string(plain) {
		t.Fatalf("round-trip mismatch:\n want %s\n got  %s", plain, got)
	}

	// 错误密钥应解密失败（GCM 认证失败）
	if _, err := decryptRef("wrong-key", enc); err == nil {
		t.Fatalf("expected auth failure with wrong key")
	}
}
