package configcenter

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"io"
	"os"
)

// 加密方案（客户端需用同一套解密）：
//   key32      = SHA-256(环境变量值)                 // 任意长度口令 → 固定 32 字节，AES-256
//   nonce      = 12 字节随机数
//   ciphertext = AES-256-GCM.Seal(plaintext)         // 密文尾部含 16 字节 GCM tag
//   输出       = Base64Std( nonce(12) || ciphertext )
// 客户端：b=base64decode(s); nonce=b[:12]; ct=b[12:]; plain=GCM.Open(nonce, ct); key32=SHA256(同一密钥)。

const devFallbackSecret = "dev-config-secret-change-me"

// deriveKey 从环境变量取密钥口令并派生 32 字节 AES-256 密钥；未配置则用开发回退（仅本地）。
func deriveKey(envName string) (key [32]byte, fromEnv bool) {
	v := os.Getenv(envName)
	if v == "" {
		v = devFallbackSecret
		return sha256.Sum256([]byte(v)), false
	}
	return sha256.Sum256([]byte(v)), true
}

// encryptJSON 用 AES-256-GCM 整包加密，返回 Base64( nonce || ciphertext )。
func encryptJSON(envName string, plaintext []byte) (string, error) {
	key, _ := deriveKey(envName)
	block, err := aes.NewCipher(key[:])
	if err != nil {
		return "", err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}
	nonce := make([]byte, gcm.NonceSize()) // 12
	if _, err = io.ReadFull(rand.Reader, nonce); err != nil {
		return "", err
	}
	ciphertext := gcm.Seal(nil, nonce, plaintext, nil)
	out := append(nonce, ciphertext...)
	return base64.StdEncoding.EncodeToString(out), nil
}
