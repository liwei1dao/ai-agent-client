package utils

import (
	"testing"
	"time"
)

// 验证按固定时区跨 0 点归日：同一 UTC 时刻在中国时区(UTC+8)下归到正确的统计日。
func TestStatDayNumber_Timezone(t *testing.T) {
	loc := LoadStatLocation("Asia/Shanghai")
	cases := []struct {
		utc  time.Time
		want uint32
	}{
		// 16:30 UTC = 次日 00:30 CST → 归到次日
		{time.Date(2026, 6, 17, 16, 30, 0, 0, time.UTC), 20260618},
		// 15:30 UTC = 当日 23:30 CST → 仍归当日
		{time.Date(2026, 6, 17, 15, 30, 0, 0, time.UTC), 20260617},
		// 跨月：05-31 16:00 UTC = 06-01 00:00 CST
		{time.Date(2026, 5, 31, 16, 0, 0, 0, time.UTC), 20260601},
		// 跨年：12-31 16:00 UTC = 次年 01-01 00:00 CST
		{time.Date(2026, 12, 31, 16, 0, 0, 0, time.UTC), 20270101},
	}
	for _, c := range cases {
		if got := StatDayNumber(c.utc, loc); got != c.want {
			t.Fatalf("StatDayNumber(%s, CST)=%d, want %d", c.utc.Format(time.RFC3339), got, c.want)
		}
	}
}

// 验证 YYYYMMDD 的数值序与日期时序一致（cleanup「statDay < yesterday」依赖此性质）。
func TestStatDayNumber_MonotonicAcrossBoundaries(t *testing.T) {
	loc := LoadStatLocation("Asia/Shanghai")
	day := func(y, m, d int) uint32 {
		return StatDayNumber(time.Date(y, time.Month(m), d, 12, 0, 0, 0, time.UTC), loc)
	}
	if !(day(2026, 1, 31) < day(2026, 2, 1)) {
		t.Fatal("跨月序错误：20260131 应 < 20260201")
	}
	if !(day(2025, 12, 31) < day(2026, 1, 1)) {
		t.Fatal("跨年序错误：20251231 应 < 20260101")
	}
}

// Asia/Shanghai 全年偏移恒为 +8h（无夏令时），fallback 到 FixedZone 也应等价。
func TestLoadStatLocation_OffsetIsPlus8(t *testing.T) {
	loc := LoadStatLocation("Asia/Shanghai")
	for _, mth := range []int{1, 6, 12} {
		_, off := time.Date(2026, time.Month(mth), 15, 12, 0, 0, 0, loc).Zone()
		if off != 8*3600 {
			t.Fatalf("Asia/Shanghai 月份%d 偏移应为 +8h, got %ds", mth, off)
		}
	}
}

// 到下一个 0 点的间隔应在 (0, 24h+5s] 内，且带 +5s 缓冲。
func TestDurationToNextMidnight_Range(t *testing.T) {
	loc := LoadStatLocation("Asia/Shanghai")
	d := DurationToNextMidnight(loc)
	if d <= 0 || d > 24*time.Hour+5*time.Second {
		t.Fatalf("DurationToNextMidnight 越界: %s", d)
	}
}
