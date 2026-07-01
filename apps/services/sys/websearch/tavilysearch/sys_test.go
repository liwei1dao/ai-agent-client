package tavilysearch_test

import (

	//"lego_bighealth/sys/coze"

	"context"
	"fmt"
	"os"
	"testing"
	tavily "yunyan/sys/websearch/tavilysearch"
)

func Test_Sys_Chat(t *testing.T) {
	apiKey := os.Getenv("TAVILY_API_KEY")
	if apiKey == "" {
		t.Skip("TAVILY_API_KEY env not set")
	}
	if sys, err := tavily.NewSys(
		tavily.SetApiKey(apiKey),
	); err != nil {
		fmt.Printf("Sys Init err:%v", err)
	} else {
		result, err := sys.Search(context.Background(), "茅台今日股价?", 5, 5)
		fmt.Printf("result:%v err:%v", result, err)
	}
}
