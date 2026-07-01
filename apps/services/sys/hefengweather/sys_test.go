package hefengweather_test

import (
	"fmt"
	"os"
	"testing"
	"yunyan/sys/hefengweather"
)

func Test_Sys(t *testing.T) {
	apiKey := os.Getenv("QWEATHER_API_KEY")
	apiHost := os.Getenv("QWEATHER_API_HOST")
	if apiKey == "" || apiHost == "" {
		t.Skip("QWEATHER_API_KEY / QWEATHER_API_HOST env not set")
	}
	if sys, err := hefengweather.NewSys(
		hefengweather.SetBaseUrl(fmt.Sprintf("https://%s", apiHost)),
		hefengweather.SetKey(apiKey),
	); err != nil {
		fmt.Printf("Sys Init err:%v", err)
	} else {
		// xal, _ := axml.NewSys()
		result, err := sys.CityLookup("武汉")
		if err != nil && result.Code != "200" {
			fmt.Printf("CityLookup err:%v", err)
			return
		}
		result1, err := sys.QueryWeather(result.Location[0].ID)
		if err != nil && result.Code != "200" {
			fmt.Printf("QueryWeather err:%v", err)
			return
		}
		fmt.Printf(" result:%v err:%v", result1, err)
	}
}
