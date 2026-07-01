package googlemap_test

import (
	"fmt"
	"os"
	"testing"
	"yunyan/sys/googlemap"
)

func Test_Sys_Geocode(t *testing.T) {
	apiKey := os.Getenv("GOOGLE_MAPS_API_KEY")
	if apiKey == "" {
		t.Skip("GOOGLE_MAPS_API_KEY env not set")
	}
	if sys, err := googlemap.NewSys(
		googlemap.SetApiKey(apiKey),
	); err != nil {
		fmt.Printf("Sys Init err:%v", err)
	} else {
		root, err := sys.Geocode("香港西九龙站")
		fmt.Printf(" root:%+v err:%v", root, err)
	}
}

func Test_Sys_NearbySearch(t *testing.T) {
	apiKey := os.Getenv("GOOGLE_MAPS_API_KEY")
	if apiKey == "" {
		t.Skip("GOOGLE_MAPS_API_KEY env not set")
	}
	if sys, err := googlemap.NewSys(
		googlemap.SetApiKey(apiKey),
	); err != nil {
		fmt.Printf("Sys Init err:%v", err)
	} else {
		root, err := sys.NearbySearch("25.0478,121.5319", "1000", "银行")
		fmt.Printf(" root:%+v err:%v", root, err)
	}
}

func Test_Sys_Navigation(t *testing.T) {
	apiKey := os.Getenv("GOOGLE_MAPS_API_KEY")
	if apiKey == "" {
		t.Skip("GOOGLE_MAPS_API_KEY env not set")
	}
	if sys, err := googlemap.NewSys(
		googlemap.SetApiKey(apiKey),
	); err != nil {
		fmt.Printf("Sys Init err:%v", err)
	} else {
		root, err := sys.Navigation("25.0478,121.5319", "25.033964,121.564468", "driving")
		fmt.Printf(" root:%+v err:%v", root, err)
	}
}
