package musicobj_test

import (
	music "yunyan/sys/musicobj"
	"fmt"
	"testing"
)

// http://www.deapsound.com:3000/search?keywords=%E7%AC%A8%E5%B0%8F%E5%AD%A9
func Test_Sys_SearchMusic(t *testing.T) {
	if sys, err := music.NewSys(
		music.SetApiBaseUrl("https://hw.music.voitrans.net"),
	); err != nil {
		fmt.Printf("Sys Init err:%v", err)
	} else {
		var (
			searchResultResponse *music.SearchResultResponse
		)
		if searchResultResponse, err = sys.SearchMusic("童年", 10, 0); err == nil {

		}
		if err != nil {
			fmt.Printf("播放音乐失败, err:%v", err)
			return
		} else {
			fmt.Printf("播放音乐成功 searchResultResponse:%+v", searchResultResponse)
		}
	}
}
