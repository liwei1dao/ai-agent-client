package aes

import (
	"fmt"
	"testing"
)

func Test_CBC(t *testing.T) {
	key, _ := GenerateRandomKey(16)
	fmt.Printf("key:%s\n", key)
	token := AesEncryptCBC("asdjoiqwjeio", key)
	fmt.Printf("encrypted:%s", token)

	origData := AesDecryptCBC(token, key)
	fmt.Printf("encrypted:%s", string(origData))
}
