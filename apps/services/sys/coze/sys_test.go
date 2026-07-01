package coze_test

import (

	//"lego_bighealth/sys/coze"

	"context"
	"fmt"
	"os"
	"testing"
	"yunyan/sys/coze"
)

func Test_Sys_Chat(t *testing.T) {
	token := os.Getenv("COZE_API_TOKEN")
	botID := os.Getenv("COZE_BOT_ID")
	if token == "" || botID == "" {
		t.Skip("COZE_API_TOKEN/COZE_BOT_ID env not set")
	}
	if sys, err := coze.NewSys(
		coze.SetToken(token),
		coze.SetBotID(botID),
	); err != nil {
		fmt.Printf("Sys Init err:%v", err)
	} else {
		result := make(chan *coze.ChatResponseChoice, 10)
		go func() {
			err := sys.ChatForSteams(context.Background(), "liwei1dao", map[string]string{"sys_lon_lat": "116.321669,39.985266"}, []coze.Message{
				{
					Role:    "user",
					Content: "给我导航到大新地铁站",
				},
			}, result)
			if err != nil {
				fmt.Printf(" err:%v", err)
				return
			}
		}()

		for v := range result {
			fmt.Printf("result:%v\n", v)
		}
	}
}
