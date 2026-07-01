package wordfilter_test

import (
	"yunyan/lego/sys/wordfilter"
	"fmt"
	"testing"
)

// 国内
func Test_sys_wordfilter(t *testing.T) {
	if sys, err := wordfilter.NewSys(
		wordfilter.SetWorldFile([]string{"./wordfilter.txt"}),
	); err == nil {
		ok, str := sys.Validate("李伟")
		fmt.Println(ok, str)
	}
}
