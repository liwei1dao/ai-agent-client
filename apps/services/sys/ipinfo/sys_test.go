package ipinfo_test

import (
	"yunyan/sys/ipinfo"
	"fmt"
	"testing"
)

func TestSys(t *testing.T) {
	sys, err := ipinfo.NewSys(
		ipinfo.SetV4XdbPath("./ip2region_v4.xdb"),
		ipinfo.SetV6XdbPath("./ip2region_v6.xdb"),
	)
	if err != nil {
		t.Fatalf("init sys: %v", err)
	}
	defer sys.Close()

	cases := []string{
		"36.152.160.156", // CN
		"8.8.8.8",        // US
		"1.1.1.1",        // AU
		"203.129.64.1",
		"103.110.204.1",
		"240e:3b7:3272:d8d0:db09:c067:8d59:539e", // CN v6
	}
	for _, ip := range cases {
		info, err := sys.GetIPInfo(ip)
		if err != nil {
			t.Errorf("ip %s query err: %v", ip, err)
			continue
		}
		fmt.Printf("IP:%-42s Country:%s(%s) Province:%s City:%s ISP:%s Continent:%s",
			info.IP, info.Country, info.CountryCode,
			info.Province, info.City, info.ISP, info.ContinentCode)
	}
}
