package amap_test

import (
	"fmt"
	"os"
	"testing"
	"yunyan/sys/amap"
)

func Test_Sys(t *testing.T) {
	apiKey := os.Getenv("AMAP_API_KEY")
	if apiKey == "" {
		t.Skip("AMAP_API_KEY env not set")
	}
	if sys, err := amap.NewSys(
		amap.SetAppkey(apiKey),
	); err != nil {
		fmt.Printf("Sys Init err:%v", err)
	} else {
		// Georesult, _ := sys.Coordinate("116.481499", "39.990475")
		// result, err := sys.Geocode("81.172193,44.604112")
		// fmt.Printf("result:%+v err:%v\n", result, err)
		// result, err := sys.Geo("北京市", "东方君悦大酒店")
		// fmt.Printf("result:%+v err:%v\n", result, err)
		// POISearchresult, _ := sys.POISearch(Georesult.Locations, "1000", "美食")
		// // fmt.Printf(" POISearchresult:%+v err:%v\n", POISearchresult, err)
		// context := ""
		// for _, item := range POISearchresult.POIs {
		// 	context += fmt.Sprintf("名称:%s,地址:%s,评分:%s,距离:%s,标签:%s;", item.Name, item.Address, item.Business.Rating, item.Distance, item.Business.Tag)
		// }
		// fmt.Println(context)
		// Weatherresult, err := sys.Weather("深圳", "all")
		// fmt.Printf(" Weatherresult:%v err:%v\n", Weatherresult, err)
		// Weatherresult, err := sys.DirectionForDriving("116.481028,39.98964", "116.434446,39.90816")
		// fmt.Printf(" Weatherresult:%+v err:%v\n", Weatherresult, err)
		// Weatherresult, err := sys.DirectionForWalking("116.481028,39.98964", "116.434446,39.90816")
		// fmt.Printf(" Weatherresult:%+v err:%v\n", Weatherresult, err)
		result, err := sys.SearchPlace("深圳北站", "深圳")
		fmt.Printf(" result:%+v err:%v\n", result, err)
		// Weatherresult, err := sys.DirectionForElectrobike("116.481028,39.98964", "116.434446,39.90816")
		// fmt.Printf(" Weatherresult:%+v err:%v\n", Weatherresult, err)
		// Weatherresult, err := sys.DirectionForTsransit("116.481028,39.98964", "116.434446,39.90816", "010", "010")
		// fmt.Printf(" Weatherresult:%+v err:%v\n", Weatherresult, err)
	}
}
