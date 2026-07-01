package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/mysql"
	"yunyan/pb"
	"fmt"
	"time"
)

// 全量重建统计所需的源表聚合查询。
// 注：以下分组使用 MySQL DATE(FROM_UNIXTIME(ts)) 按服务器时区切日，
// 与事件驱动写入 time.Now().Format("2006-01-02") 的本地时区一致。

// orderCreateAgg 创建订单数（按 create_time 切日）
type dateCountRow struct {
	D     string `gorm:"column:d"`
	Count int64  `gorm:"column:cnt"`
}

// dateSumPayRow 已支付订单 SUM(amount)/COUNT(*)/COUNT(DISTINCT uid) （按 pay_time 切日）
type dateSumPayRow struct {
	D         string `gorm:"column:d"`
	Count     int64  `gorm:"column:cnt"`
	Amount    int64  `gorm:"column:amt"`
	UserCount int64  `gorm:"column:ucnt"`
}

// dateUseLogRow 资源发放（按 ts 切日，4 个发放字段 SUM）
type dateUseLogRow struct {
	D           string `gorm:"column:d"`
	AddVipDay   int64  `gorm:"column:vipday"`
	AddAgentInt int64  `gorm:"column:aichat"`
	AddTradeSec int64  `gorm:"column:tradesec"`
	AddMeetSec  int64  `gorm:"column:meetsec"`
}

// aggOrderCreate 按创建日聚合 order_count
func (this *modelComp) aggOrderCreate() (rows []*dateCountRow, err error) {
	rows = make([]*dateCountRow, 0)
	err = mysql.Table(comm.TablePayOrder).
		Select("DATE_FORMAT(FROM_UNIXTIME(create_time), '%Y-%m-%d') AS d, COUNT(*) AS cnt").
		Where("create_time > 0").
		Group("d").
		Scan(&rows).Error
	return
}

// aggOrderFailed 按创建日聚合 failed_order_count（失败订单按 create_time 切日）
func (this *modelComp) aggOrderFailed() (rows []*dateCountRow, err error) {
	rows = make([]*dateCountRow, 0)
	err = mysql.Table(comm.TablePayOrder).
		Select("DATE_FORMAT(FROM_UNIXTIME(create_time), '%Y-%m-%d') AS d, COUNT(*) AS cnt").
		Where("create_time > 0 AND status = ?", int32(pb.PayOrderStatus_PAY_ORDER_FAILED)).
		Group("d").
		Scan(&rows).Error
	return
}

// aggOrderPaid 按支付日聚合 pay_amount/pay_count/pay_user_count
func (this *modelComp) aggOrderPaid() (rows []*dateSumPayRow, err error) {
	rows = make([]*dateSumPayRow, 0)
	err = mysql.Table(comm.TablePayOrder).
		Select("DATE_FORMAT(FROM_UNIXTIME(pay_time), '%Y-%m-%d') AS d, COUNT(*) AS cnt, COALESCE(SUM(amount),0) AS amt, COUNT(DISTINCT uid) AS ucnt").
		Where("pay_time > 0 AND status = ?", int32(pb.PayOrderStatus_PAY_ORDER_PAID)).
		Group("d").
		Scan(&rows).Error
	return
}

// aggUserSignup 按注册日聚合 new_user_count
func (this *modelComp) aggUserSignup() (rows []*dateCountRow, err error) {
	rows = make([]*dateCountRow, 0)
	err = mysql.Table(comm.TableUser).
		Select("DATE_FORMAT(FROM_UNIXTIME(createtime), '%Y-%m-%d') AS d, COUNT(*) AS cnt").
		Where("createtime > 0").
		Group("d").
		Scan(&rows).Error
	return
}

// aggUseLogGrant 按日聚合资源发放（vipday/aichat/trade-sec/meet-sec）
func (this *modelComp) aggUseLogGrant() (rows []*dateUseLogRow, err error) {
	rows = make([]*dateUseLogRow, 0)
	err = mysql.Table(comm.TableUserUseLog).
		Select("DATE_FORMAT(FROM_UNIXTIME(ts), '%Y-%m-%d') AS d, " +
			"COALESCE(SUM(addvipday),0) AS vipday, " +
			"COALESCE(SUM(addagentintegral),0) AS aichat, " +
			"COALESCE(SUM(addtradesecond),0) AS tradesec, " +
			"COALESCE(SUM(addmeetsecond),0) AS meetsec").
		Where("ts > 0").
		Group("d").
		Scan(&rows).Error
	return
}

// 全局累计字段（无法按日还原，只能 SUM 整库）

// sumLifetimePayments 全部已支付订单累计金额、订单数、付费人数（去重 uid）
func (this *modelComp) sumLifetimePayments() (payAmount, payCount, payUserCount, orderCount, failedOrderCount int64, err error) {
	type r struct {
		Amount int64 `gorm:"column:amt"`
		Count  int64 `gorm:"column:cnt"`
		UCnt   int64 `gorm:"column:ucnt"`
	}
	var rr r
	if err = mysql.Table(comm.TablePayOrder).
		Select("COALESCE(SUM(amount),0) AS amt, COUNT(*) AS cnt, COUNT(DISTINCT uid) AS ucnt").
		Where("status = ?", int32(pb.PayOrderStatus_PAY_ORDER_PAID)).
		Scan(&rr).Error; err != nil {
		return
	}
	payAmount, payCount, payUserCount = rr.Amount, rr.Count, rr.UCnt
	if err = mysql.Table(comm.TablePayOrder).Count(&orderCount).Error; err != nil {
		return
	}
	err = mysql.Table(comm.TablePayOrder).
		Where("status = ?", int32(pb.PayOrderStatus_PAY_ORDER_FAILED)).
		Count(&failedOrderCount).Error
	return
}

// sumLifetimeUseLog 全部资源发放累计（用于 global 行 add_* 字段）
func (this *modelComp) sumLifetimeUseLog() (vipDay, aiInt, tradeSec, meetSec int64, err error) {
	type r struct {
		Vipday   int64 `gorm:"column:vipday"`
		Aichat   int64 `gorm:"column:aichat"`
		Tradesec int64 `gorm:"column:tradesec"`
		Meetsec  int64 `gorm:"column:meetsec"`
	}
	var rr r
	err = mysql.Table(comm.TableUserUseLog).
		Select("COALESCE(SUM(addvipday),0) AS vipday, " +
			"COALESCE(SUM(addagentintegral),0) AS aichat, " +
			"COALESCE(SUM(addtradesecond),0) AS tradesec, " +
			"COALESCE(SUM(addmeetsecond),0) AS meetsec").
		Scan(&rr).Error
	vipDay, aiInt, tradeSec, meetSec = rr.Vipday, rr.Aichat, rr.Tradesec, rr.Meetsec
	return
}

// sumLifetimeUserStats 从 userstatistics 表汇总累计消耗（用于 global 行的 ai/trade/meet 字段）
func (this *modelComp) sumLifetimeUserStats() (aiChat, aiUp, aiDown, tradeCount, tradeTime, tradeWords, meetCount, meetTime int64, err error) {
	type r struct {
		AiChat     int64 `gorm:"column:aichat"`
		AiUp       int64 `gorm:"column:aiup"`
		AiDown     int64 `gorm:"column:aidown"`
		TradeCount int64 `gorm:"column:tcnt"`
		TradeTime  int64 `gorm:"column:ttime"`
		TradeWords int64 `gorm:"column:twords"`
		MeetCount  int64 `gorm:"column:mcnt"`
		MeetTime   int64 `gorm:"column:mtime"`
	}
	var rr r
	err = mysql.Table(comm.TableUserStatistics).
		Select("COALESCE(SUM(aichatnum),0) AS aichat, " +
			"COALESCE(SUM(aichatuptoken),0) AS aiup, " +
			"COALESCE(SUM(aichatdowntoken),0) AS aidown, " +
			"COALESCE(SUM(" + colTradeNumSum + "),0) AS tcnt, " +
			"COALESCE(SUM(" + colTradeTimeSum + "),0) AS ttime, " +
			"COALESCE(SUM(tradewordcount),0) AS twords, " +
			"COALESCE(SUM(meetnum),0) AS mcnt, " +
			"COALESCE(SUM(meettime),0) AS mtime").
		Scan(&rr).Error
	aiChat, aiUp, aiDown = rr.AiChat, rr.AiUp, rr.AiDown
	tradeCount, tradeTime, tradeWords = rr.TradeCount, rr.TradeTime, rr.TradeWords
	meetCount, meetTime = rr.MeetCount, rr.MeetTime
	return
}

// countUserDevices 累计绑定设备数
func (this *modelComp) countUserDevices() (total int64, err error) {
	err = mysql.Table(comm.TableUserdevice).Count(&total).Error
	return
}

// countActiveVipUsers 当前仍有效的 VIP 用户数（vipexptime > now）；用于 global 行 vip_user_count 字段
func (this *modelComp) countActiveVipUsers(nowTs int64) (total int64, err error) {
	err = mysql.Table(comm.TableUser).Where("vipexptime > ?", nowTs).Count(&total).Error
	return
}

// truncateStatTables 清空 4 张统计表（在 stat_consumer 锁内调用）
func (this *modelComp) truncateStatTables() (err error) {
	for _, tbl := range []string{
		comm.TableAppStatDaily,
		comm.TableAppStatMonthly,
		comm.TableAppStatYearly,
		comm.TableAppStatGlobal,
	} {
		if err = mysql.Exec("TRUNCATE TABLE " + tbl).Error; err != nil {
			return
		}
	}
	return
}

// insertStatRows 批量插入（已 TRUNCATE 后调用）
func (this *modelComp) insertStatRows(tbl string, rows []*pb.DBAppStat) (err error) {
	if len(rows) == 0 {
		return
	}
	const batch = 500
	for i := 0; i < len(rows); i += batch {
		j := i + batch
		if j > len(rows) {
			j = len(rows)
		}
		if err = mysql.Table(tbl).CreateInBatches(rows[i:j], batch).Error; err != nil {
			return
		}
	}
	return
}

// rebuildUserStatisticsFromLogs 从 useruselog + echomeet_record 全量重建 userstatistics。
//
// Phase 1 — useruselog（logtype=UserConsume）：
//   - addagentintegral < 0 → 翻译/AI 消耗，合并到 trademodel1_time/trademodel1_num
//   - addmeetsecond    < 0 → 实时会议（UsageType_Meet 路径）消耗
//
// Phase 2 — echomeet_record：
//
//	echomeet 启动任务时直接扣 meetintegral，未写 useruselog；
//	state > 0 且 != TranscribeFail(10002) 的记录表示积分已扣且未退款。
//	使用 ON DUPLICATE KEY UPDATE 累加到 Phase 1 已写入的行。
//
// 步骤：先 TRUNCATE，再两阶段 INSERT，保证幂等。
func (this *modelComp) rebuildUserStatisticsFromLogs() (rowsInserted int64, err error) {
	if err = mysql.Exec(fmt.Sprintf("TRUNCATE TABLE %s", comm.TableUserStatistics)).Error; err != nil {
		return
	}
	// Phase 1: 从 useruselog 聚合翻译消耗 + 实时会议消耗
	sql1 := fmt.Sprintf(
		`INSERT INTO %s (uid, meetnum, meettime, trademodel1_num, trademodel1_time)
		 SELECT
		     uid,
		     SUM(CASE WHEN addmeetsecond    < 0 THEN 1 ELSE 0 END),
		     COALESCE(SUM(CASE WHEN addmeetsecond    < 0 THEN -addmeetsecond    ELSE 0 END), 0),
		     SUM(CASE WHEN addagentintegral < 0 THEN 1 ELSE 0 END),
		     COALESCE(SUM(CASE WHEN addagentintegral < 0 THEN -addagentintegral ELSE 0 END), 0)
		 FROM %s
		 WHERE logtype = ?
		 GROUP BY uid`,
		comm.TableUserStatistics, comm.TableUserUseLog,
	)
	tx1 := mysql.Exec(sql1, int32(pb.UserLogType_UserConsume))
	if tx1.Error != nil {
		err = tx1.Error
		return
	}
	rowsInserted += tx1.RowsAffected

	// Phase 2: 从 echomeet_record 聚合文件转写会议消耗
	// state > 0: 任务已启动（积分已扣）
	// state != 10002 (TranscribeFail): 短音频失败时积分会退款，排除
	sql2 := fmt.Sprintf(
		`INSERT INTO %s (uid, meetnum, meettime)
		 SELECT uid, COUNT(*) AS meetnum, COALESCE(SUM(seconds), 0) AS meettime
		 FROM %s
		 WHERE state > 0 AND state != ? AND seconds > 0
		 GROUP BY uid
		 ON DUPLICATE KEY UPDATE
		     meetnum  = meetnum  + VALUES(meetnum),
		     meettime = meettime + VALUES(meettime)`,
		comm.TableUserStatistics, comm.TableEchomeetRecord,
	)
	tx2 := mysql.Exec(sql2, int32(pb.DBEchoMeetRecordState_TranscribeFail))
	if tx2.Error != nil {
		err = tx2.Error
		return
	}
	rowsInserted += tx2.RowsAffected
	return
}

// 产品激活/绑定统计重建 ----------------------------------------------------------

// productDeviceAgg userdevice 按 productid 聚合的中间结果
type productDeviceAgg struct {
	Productid uint32 `gorm:"column:productid"`
	Activated int64  `gorm:"column:activated"`
	Bound     int64  `gorm:"column:bound"`
}

// aggUserDeviceByProduct 按 productid 聚合 userdevice：
//
//	activated = 该产品的设备绑定记录行数（激活设备数）
//	bound     = 该产品去重后的非空 uid 数（绑定用户数）
//
// NULLIF(uid,”) 把空串转 NULL，使 COUNT(DISTINCT) 自动忽略未绑定用户的记录。
func (this *modelComp) aggUserDeviceByProduct() (rows []*productDeviceAgg, err error) {
	rows = make([]*productDeviceAgg, 0)
	err = mysql.Table(comm.TableUserdevice).
		Select("productid, COUNT(*) AS activated, COUNT(DISTINCT NULLIF(uid,'')) AS bound").
		Group("productid").
		Scan(&rows).Error
	return
}

// rebuildProductStats 全量重建 product_stat：
// 扫描整张 userdevice 表汇总每个产品的激活设备数 / 绑定用户数，
// 并为 product 表中尚无设备的产品补 0 行，保证“所有产品”都有一条统计；
// 最后 TRUNCATE 后整表改写。返回写入的行数。
func (this *modelComp) rebuildProductStats() (rows int, err error) {
	agg, err := this.aggUserDeviceByProduct()
	if err != nil {
		return
	}
	now := time.Now().Unix()
	statMap := make(map[uint32]*pb.DBProductStat, len(agg))
	for _, a := range agg {
		if a.Productid == 0 { // userdevice 中无产品归属的脏数据，仪表盘不会查询，跳过
			continue
		}
		statMap[a.Productid] = &pb.DBProductStat{
			Productid:      a.Productid,
			ActivatedCount: a.Activated,
			BoundUserCount: a.Bound,
			UpdateTime:     now,
		}
	}
	// product 表里尚无设备的产品补 0 行
	products, perr := this.products()
	if perr != nil {
		err = perr
		return
	}
	for _, p := range products {
		if _, ok := statMap[p.Id]; !ok {
			statMap[p.Id] = &pb.DBProductStat{Productid: p.Id, UpdateTime: now}
		}
	}
	list := make([]*pb.DBProductStat, 0, len(statMap))
	for _, v := range statMap {
		list = append(list, v)
	}
	if err = mysql.Exec("TRUNCATE TABLE " + comm.TableProductStat).Error; err != nil {
		return
	}
	rows = len(list)
	if len(list) == 0 {
		return
	}
	const batch = 500
	for i := 0; i < len(list); i += batch {
		j := i + batch
		if j > len(list) {
			j = len(list)
		}
		if err = mysql.Table(comm.TableProductStat).CreateInBatches(list[i:j], batch).Error; err != nil {
			return
		}
	}
	return
}
