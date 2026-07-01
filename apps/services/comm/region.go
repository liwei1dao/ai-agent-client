package comm

// 区域代码：与 pb.Region 枚举值一一对应的英文短代码，用于 stats_global_day.region 等可读字段。
// console 历史分析、analyze 实时写入、运维统计都用同一套代码，保证跨来源一致。
var regionCodes = map[int32]string{
	0:  "",    // RegionUnknown
	1:  "cn",  // 中国
	2:  "us",  // 美国
	3:  "ea",  // 东亚
	4:  "sea", // 东南亚
	5:  "sa",  // 南亚
	6:  "me",  // 中东
	7:  "eu",  // 欧洲
	8:  "ru",  // 俄罗斯
	9:  "af",  // 非洲
	10: "sam", // 南美
	11: "nam", // 北美
	12: "oc",  // 大洋洲
	13: "br",  // 巴西
	14: "in",  // 印度
}

// RegionCode 把 pb.Region 枚举值（int32）转成英文短代码；未知返回空串。
func RegionCode(region int32) string {
	if c, ok := regionCodes[region]; ok {
		return c
	}
	return ""
}
