package utils

import "time"

// 统计日界的统一时区工具。
//
// analyze（业务侧）与 console（汇总侧）都按「统计日」(YYYYMMDD) 分桶累计，跨 0 点切日。
// 若各部署用机器本地时区算 0 点，多区域机器时区不一致会让日界错位；故统一走可配的固定时区，
// 默认 Asia/Shanghai（中国时区，无夏令时）。两侧共用同一套函数，保证口径一致。

// LoadStatLocation 解析统计时区名；name 为空用 Asia/Shanghai。
// LoadLocation 失败（如容器缺 tzdata、名称非法）时回退到固定 UTC+8 ——
// 对默认的中国时区即便没有 tzdata 也能正确切日；其它具名时区请确保 main 引入 time/tzdata。
func LoadStatLocation(name string) *time.Location {
	if name == "" {
		name = "Asia/Shanghai"
	}
	if loc, err := time.LoadLocation(name); err == nil {
		return loc
	}
	return time.FixedZone("UTC+8", 8*3600)
}

// StatDayNumber 按给定时区把时间转成 YYYYMMDD 形式的统计日。loc 为 nil 时按 t 自身时区。
func StatDayNumber(t time.Time, loc *time.Location) uint32 {
	if loc != nil {
		t = t.In(loc)
	}
	y, m, d := t.Date()
	return uint32(y*10000 + int(m)*100 + d)
}

// DurationToNextMidnight 返回从现在到「给定时区的下一个 0 点」的间隔，额外 +5s 缓冲，
// 确保越过 0 点、让在途事件落定后再触发跨日收尾。loc 为 nil 用本地时区。
func DurationToNextMidnight(loc *time.Location) time.Duration {
	now := time.Now()
	if loc != nil {
		now = now.In(loc)
	} else {
		loc = now.Location()
	}
	next := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, loc).AddDate(0, 0, 1)
	return next.Sub(now) + 5*time.Second
}
