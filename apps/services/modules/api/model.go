package api

import (
	"yunyan/comm"
	"yunyan/lego/core"
	"yunyan/lego/core/cbase"
	"yunyan/lego/sys/mysql"
	"yunyan/lego/sys/postgres"
	"yunyan/pb"
	"yunyan/sys/appstat"
	"fmt"

	"gorm.io/gorm"
)

// 代理模型
type modelComp struct {
	cbase.ModuleCompBase
	module *API
}

// 组件初始化接口
func (this *modelComp) Init(service core.IService, module core.IModule, comp core.IModuleComp, opt core.IModuleOptions) (err error) {
	this.ModuleCompBase.Init(service, module, comp, opt)
	this.module = module.(*API)
	if err = mysql.CreateTable(comm.TableAdmin, &pb.DBAdminUser{}); err != nil {
		this.module.Errorln(err)
	}
	if err = mysql.CreateTable(comm.TableUserUseLog, &pb.DBUserUseLog{}); err != nil {
		this.module.Errorln(err)
	}
	if err = mysql.CreateTable(comm.TableAdminResLog, &pb.DBAdminResourceLog{}); err != nil {
		this.module.Errorln(err)
	}
	if err = mysql.CreateTable(comm.TableAppConfig, &pb.DBAppConfigItem{}); err != nil {
		this.module.Errorln(err)
	}
	if err = mysql.CreateTable(comm.TableAppConfig, &pb.DBAppConfigItem{}); err != nil {
		this.module.Errorln(err)
	}
	if err = postgres.CreateTable(comm.TableGlobalConfig, &pb.DBGlobalConfigItem{}); err != nil {
		this.module.Errorln(err)
	}
	if err = mysql.CreateTable(comm.TableAgent, &pb.DBAgent{}); err != nil {
		this.module.Errorln(err)
	}
	if err = postgres.CreateTable(comm.TableMcp, &pb.DBMcpServer{}); err != nil {
		this.module.Errorln(err)
	}
	if err = mysql.CreateTable(comm.TableEchomeetRecord, &pb.DBEchoMeetRecord{}); err != nil {
		this.module.Errorln(err)
	}
	if err = mysql.CreateTable(comm.TableEchomeetTemplate, &pb.DBEchoMeetTemplate{}); err != nil {
		this.module.Errorln(err)
	} else {
		mysql.Exec(fmt.Sprintf("ALTER TABLE %s AUTO_INCREMENT = %d", comm.TableEchomeetTemplate, 10000))
	}
	if err = postgres.CreateTable(comm.TableEchomeetTemplate, &pb.DBEchoMeetTemplate{}); err != nil {
		this.module.Errorln(err)
	}
	if err = mysql.CreateTable(comm.TableWakeupVoice, &pb.DBWakeupVoice{}); err != nil {
		this.module.Errorln(err)
	}

	if err = postgres.CreateTable(comm.TableFactory, &pb.DBFactory{}); err != nil {
		this.module.Errorln(err)
	} else {
		//设置factory表的主键从0xA001开始（仅空表生效，跨 MySQL/Postgres 通用）
		postgres.AutoIncrementStart(comm.TableFactory, "id", 0xA001)
	}
	if err = postgres.CreateTable(comm.TableFactoryDeliveryNote, &pb.DBFactoryDeliveryNote{}); err != nil {
		this.module.Errorln(err)
	}
	if err = postgres.CreateTable(comm.TableProduct, &pb.DBProduct{}); err != nil {
		this.module.Errorln(err)
	} else {
		//设置product表的主键从0xB001开始（仅空表生效，跨 MySQL/Postgres 通用）
		postgres.AutoIncrementStart(comm.TableProduct, "id", 0xB001)
	}
	if err = postgres.CreateTable(comm.TableProductVersion, &pb.DBProductVersion{}); err != nil {
		this.module.Errorln(err)
	}
	if err = mysql.CreateTable(comm.TableChannelApp, &pb.DBChannelApp{}); err != nil {
		this.module.Errorln(err)
	}
	if err = postgres.CreateTable(comm.TableLicense, &pb.DBFactoryDevics{}); err != nil {
		this.module.Errorln(err)
		return err
	}
	if err = postgres.CreateTable(comm.TableFactoryPublicCode, &pb.DBFactoryPublicCode{}); err != nil {
		this.module.Errorln(err)
		return err
	}
	if err = mysql.CreateTable(comm.TableGoods, &pb.DBGoods{}); err != nil {
		this.module.Errorln(err)
		return err
	}
	if err = postgres.CreateTable(comm.TableWakeupVoice, &pb.DBWakeupVoice{}); err != nil {
		this.module.Errorln(err)
		return err
	} else {
		//设置wakeupvoice表的主键从0xD001开始（仅空表生效，跨 MySQL/Postgres 通用）
		postgres.AutoIncrementStart(comm.TableWakeupVoice, "id", 0xD001)
	}
	if err = mysql.CreateTable(comm.TableAppStatDaily, &pb.DBAppStat{}); err != nil {
		this.module.Errorln(err)
	}
	if err = mysql.CreateTable(comm.TableAppStatMonthly, &pb.DBAppStat{}); err != nil {
		this.module.Errorln(err)
	}
	if err = mysql.CreateTable(comm.TableAppStatYearly, &pb.DBAppStat{}); err != nil {
		this.module.Errorln(err)
	}
	if err = mysql.CreateTable(comm.TableAppStatGlobal, &pb.DBAppStat{}); err != nil {
		this.module.Errorln(err)
	}
	if err = mysql.CreateTable(comm.TableProductStat, &pb.DBProductStat{}); err != nil {
		this.module.Errorln(err)
	}
	// AutoMigrate 不会主动放宽已存在列的 varchar 宽度，
	// 历史库 stat_date 可能是更短的 varchar(N<10)，导致写入 "YYYY-MM-DD" 报 1406 Data too long。
	// 这里强制把 4 张表的 stat_date 拉到 varchar(20)，幂等。
	for _, tbl := range []string{
		comm.TableAppStatDaily,
		comm.TableAppStatMonthly,
		comm.TableAppStatYearly,
		comm.TableAppStatGlobal,
	} {
		if e := mysql.Exec(fmt.Sprintf("ALTER TABLE %s MODIFY COLUMN stat_date VARCHAR(20) NOT NULL", tbl)).Error; e != nil {
			this.module.Errorln(e)
		}
	}
	model := &pb.DBAdminUser{
		Account:  this.module.options.AdninAccount,
		Password: this.module.options.AdninPassword,
		Identity: pb.Identity_Admin,
	}
	// 执行分页查询
	mysql.Insert(comm.TableAdmin, model)
	return
}
func (this *modelComp) Start() (err error) {
	if err = this.ModuleCompBase.Start(); err != nil {
		return err
	}
	var products []*pb.DBProduct
	if err = postgres.Find(comm.TableProduct, &products, ""); err != nil && err != mysql.ErrNoDocuments {
		this.module.Errorln(err)
		return err
	}
	for _, v := range products {
		if err = postgres.CreateTable(fmt.Sprintf("%s_%x", comm.TableLicense, v.Id), &pb.DBFactoryDevics{}); err != nil {
			this.module.Errorln(err)
			return err
		}
	}
	// product_stat 为空（首次部署 / 从未点过重建）时做一次初始扫描，
	// 避免代理仪表盘在首次重建前激活数/绑定用户数全部显示 0。
	var statCount int64
	if cerr := mysql.Table(comm.TableProductStat).Count(&statCount).Error; cerr != nil {
		this.module.Errorln(cerr)
	} else if statCount == 0 {
		if n, rerr := this.rebuildProductStats(); rerr != nil {
			this.module.Errorln(rerr)
		} else {
			this.module.Infof("product_stat 初始扫描完成, rows=%d", n)
		}
	}
	return
}

// 寻找账号
func (this *modelComp) findforaccount(account string) (user *pb.DBAdminUser, err error) {
	user = &pb.DBAdminUser{}
	err = mysql.FindOne(comm.TableAdmin, user, "account=?", account)
	return
}

// 添加管理员账号
func (this *modelComp) addAdminUser(user *pb.DBAdminUser) (err error) {
	err = mysql.Insert(comm.TableAdmin, user)
	return
}

// 删除管理员账号
func (this *modelComp) delAdminUser(account string) (err error) {
	err = mysql.Delete(comm.TableAdmin, "account=?", account)
	return
}

// 更新管理员账号
func (this *modelComp) updateAdminUser(user *pb.DBAdminUser) (err error) {
	err = mysql.Save(comm.TableAdmin, user)
	return
}

// 查询管理员账号列表
func (this *modelComp) getAdminUsers() (users []*pb.DBAdminUser, err error) {
	err = mysql.Find(comm.TableAdmin, &users, "")
	return
}

// adjustAdminBalance 用 SQL 表达式 (col = col + ?) 原子调整指定账号的资源点余额。
// 仅写入 delta != 0 的列，避免 Save 覆盖其它字段，也避免并发派发互相覆盖。
// 返回 rowsAffected 用于校验账号是否存在。delta 可正(增加/赠送) 可负(扣减/派发)。
func (this *modelComp) adjustAdminBalance(account string, dVipday, dAichat, dTradeSec, dMeetSec int64) (rowsAffected int64, err error) {
	updates := map[string]any{}
	if dVipday != 0 {
		updates["vipday_balance"] = gorm.Expr("vipday_balance + ?", dVipday)
	}
	if dAichat != 0 {
		updates["aichatintegral_balance"] = gorm.Expr("aichatintegral_balance + ?", dAichat)
	}
	if dTradeSec != 0 {
		updates["tradesecond_balance"] = gorm.Expr("tradesecond_balance + ?", dTradeSec)
	}
	if dMeetSec != 0 {
		updates["meetsecond_balance"] = gorm.Expr("meetsecond_balance + ?", dMeetSec)
	}
	if len(updates) == 0 {
		return
	}
	tx := mysql.Table(comm.TableAdmin).Where("account=?", account).Updates(updates)
	rowsAffected = tx.RowsAffected
	err = tx.Error
	return
}

// 寻找用户
func (this *modelComp) finduser(uid string) (user *pb.DBUser, err error) {
	user = &pb.DBUser{}
	err = mysql.FindOne(comm.TableUser, user, "uid=?", uid)
	return
}

// 寻找用户 手机号
func (this *modelComp) finduserbyphone(phone string) (user *pb.DBUser, err error) {
	user = &pb.DBUser{}
	err = mysql.FindOne(comm.TableUser, user, "phone=?", phone)
	return
}

// 寻找用户 邮箱
func (this *modelComp) finduserbyemail(mail string) (user *pb.DBUser, err error) {
	user = &pb.DBUser{}
	err = mysql.FindOne(comm.TableUser, user, "mail=?", mail)
	return
}

// 寻找用户
func (this *modelComp) finduserdevice(uid string) (models []*pb.DBUserDivice, err error) {
	models = make([]*pb.DBUserDivice, 0)
	err = mysql.Find(comm.TableUserdevice, &models, "uid=?", uid)
	return
}

// 寻找用户
func (this *modelComp) deluserdevice(uid string) (err error) {
	err = mysql.Delete(comm.TableUserdevice, "uid=?", uid)
	return
}

// 更新用户信息
func (this *modelComp) updateuser(user *pb.DBUser) (err error) {
	err = mysql.Save(comm.TableUser, user)
	return
}

// 配置项
func (this *modelComp) config() (config []*pb.DBAppConfigItem, err error) {
	config = make([]*pb.DBAppConfigItem, 0)
	err = mysql.Find(comm.TableAppConfig, &config, "")
	return
}

// 添加配置
func (this *modelComp) addconfig(config ...*pb.DBAppConfigItem) (err error) {
	err = mysql.Insert(comm.TableAppConfig, config)
	return
}

// 更新配置
func (this *modelComp) updateconfig(config ...*pb.DBAppConfigItem) (err error) {
	err = mysql.Save(comm.TableAppConfig, config)
	return
}

func (this *modelComp) delconfig(id uint64) (err error) {
	err = mysql.Delete(comm.TableAppConfig, "id=?", id)
	return
}

// 全局第三方服务配置
func (this *modelComp) globalconfig() (config []*pb.DBGlobalConfigItem, err error) {
	config = make([]*pb.DBGlobalConfigItem, 0)
	err = postgres.Find(comm.TableGlobalConfig, &config, "")
	return
}
func (this *modelComp) globalconfigbyregion(region pb.Region) (config []*pb.DBGlobalConfigItem, err error) {
	config = make([]*pb.DBGlobalConfigItem, 0)
	err = postgres.Find(comm.TableGlobalConfig, &config, "region=?", region)
	return
}
func (this *modelComp) addglobalconfig(config ...*pb.DBGlobalConfigItem) (err error) {
	err = postgres.Insert(comm.TableGlobalConfig, config)
	return
}

func (this *modelComp) updateglobalconfig(config ...*pb.DBGlobalConfigItem) (err error) {
	err = postgres.Save(comm.TableGlobalConfig, config)
	return
}

func (this *modelComp) delglobalconfig(ids []uint64) (err error) {
	err = postgres.Delete(comm.TableGlobalConfig, "id IN ?", ids)
	return
}

// 智能体
func (this *modelComp) agents() (agents []*pb.DBAgent, err error) {
	agents = make([]*pb.DBAgent, 0)
	err = mysql.Find(comm.TableAgent, &agents, "")
	return
}

// 智能体
func (this *modelComp) agent(id string) (agent *pb.DBAgent, err error) {
	agent = &pb.DBAgent{}
	err = mysql.Find(comm.TableAgent, agent, "id=?", id)
	return
}

// 智能体
func (this *modelComp) addagent(agent *pb.DBAgent) (err error) {
	err = mysql.Insert(comm.TableAgent, agent)
	return
}

func (this *modelComp) updateagent(agent *pb.DBAgent) (err error) {
	err = mysql.Save(comm.TableAgent, agent)
	return
}
func (this *modelComp) delagent(id string) (err error) {
	err = mysql.Delete(comm.TableAgent, "id=?", id)
	return
}

// Mcp 服务
func (this *modelComp) mcpservers(region pb.Region) (servers []*pb.DBMcpServer, err error) {
	servers = make([]*pb.DBMcpServer, 0)
	err = postgres.Find(comm.TableMcp, &servers, "region=?", region)
	return
}

// Mcp 服务
func (this *modelComp) mcpserver(id string) (server *pb.DBMcpServer, err error) {
	server = &pb.DBMcpServer{}
	err = postgres.Find(comm.TableMcp, server, "id=?", id)
	return
}
func (this *modelComp) addmcpservers(server []*pb.DBMcpServer) (err error) {
	err = postgres.Insert(comm.TableMcp, server)
	return
}

func (this *modelComp) updatemcpservers(server []*pb.DBMcpServer) (err error) {
	err = postgres.Save(comm.TableMcp, server)
	return
}
func (this *modelComp) delmcpservers(ids []string) (err error) {
	err = postgres.Delete(comm.TableMcp, "id IN ?", ids)
	return
}

// 厂商列表
func (this *modelComp) factorys() (models []*pb.DBFactory, err error) {
	models = make([]*pb.DBFactory, 0)
	err = postgres.Find(comm.TableFactory, &models, "")
	return
}
func (this *modelComp) factory(id uint32) (model *pb.DBFactory, err error) {
	model = &pb.DBFactory{}
	err = postgres.Find(comm.TableFactory, model, "id=?", id)
	return
}
func (this *modelComp) addfactory(model *pb.DBFactory) (err error) {
	err = postgres.Insert(comm.TableFactory, model)
	return
}
func (this *modelComp) savefactory(model *pb.DBFactory) (err error) {
	err = postgres.Save(comm.TableFactory, model)
	return
}
func (this *modelComp) delfactory(id uint32) (err error) {
	err = postgres.Delete(comm.TableFactory, "id=?", id)
	return
}

// 查询设备
func (this *modelComp) products() (models []*pb.DBProduct, err error) {
	models = make([]*pb.DBProduct, 0)
	err = postgres.Find(comm.TableProduct, &models, "")
	return
}

// 查询设备
func (this *modelComp) product(id uint32) (model *pb.DBProduct, err error) {
	model = &pb.DBProduct{}
	err = postgres.FindOne(comm.TableProduct, model, "id=?", id)
	return
}

// 更新设备
func (this *modelComp) addproducts(products ...*pb.DBProduct) (err error) {
	if err = postgres.Insert(comm.TableProduct, products); err != nil {
		return err
	}
	for _, v := range products {
		if err = postgres.CreateTable(fmt.Sprintf("%s_%x", comm.TableLicense, v.Id), &pb.DBFactoryDevics{}); err != nil {
			this.module.Errorln(err)
			return err
		}
	}
	return
}

// 更新设备信息
func (this *modelComp) updateproducts(equipment *pb.DBProduct) (err error) {
	err = postgres.Save(comm.TableProduct, equipment)
	return
}
func (this *modelComp) delproducts(id uint32) (err error) {
	err = postgres.Delete(comm.TableProduct, "id=?", id)
	return
}

// 更新产品版本
func (this *modelComp) addproductversion(version *pb.DBProductVersion) (err error) {
	err = postgres.Insert(comm.TableProductVersion, version)
	return
}

// 查询设备
func (this *modelComp) productversions(pid uint32) (models []*pb.DBProductVersion, err error) {
	models = make([]*pb.DBProductVersion, 0)
	err = postgres.Find(comm.TableProductVersion, &models, "productid=?", pid)
	return
}

// 查询单个产品版本
func (this *modelComp) productversion(id uint32) (model *pb.DBProductVersion, err error) {
	model = &pb.DBProductVersion{}
	err = postgres.FindOne(comm.TableProductVersion, model, "id=?", id)
	return
}

// 更新产品版本
func (this *modelComp) delproductversion(id uint32) (err error) {
	err = postgres.Delete(comm.TableProductVersion, "id=?", id)
	return
}

// ChannelApp--------------------------------------------------------------
// 查询设备
func (this *modelComp) channelapps() (models []*pb.DBChannelApp, err error) {
	models = make([]*pb.DBChannelApp, 0)
	err = mysql.Find(comm.TableChannelApp, &models, "")
	return
}

// 查询设备
func (this *modelComp) channelapp(channel int32) (model *pb.DBChannelApp, err error) {
	model = &pb.DBChannelApp{}
	err = mysql.FindOne(comm.TableChannelApp, model, "channel=?", channel)
	return
}

// 更新设备
func (this *modelComp) addchannelapp(channelapp ...*pb.DBChannelApp) (err error) {
	err = mysql.Insert(comm.TableChannelApp, channelapp)
	return
}

// 更新设备信息
func (this *modelComp) updatechannelapp(channelapp *pb.DBChannelApp) (err error) {
	err = mysql.Save(comm.TableChannelApp, channelapp)
	return
}
func (this *modelComp) delchannelapp(channel int32) (err error) {
	err = mysql.Delete(comm.TableChannelApp, "channel=?", channel)
	return
}

// 厂家生产日志------------------------------
func (this *modelComp) factorydeliverynotes(query interface{}, args ...interface{}) (models []*pb.DBFactoryDeliveryNote, err error) {
	models = make([]*pb.DBFactoryDeliveryNote, 0)
	err = postgres.Find(comm.TableFactoryDeliveryNote, &models, query, args...)
	return
}

func (this *modelComp) factorydeliverynote(factoryid uint32, probatch uint32) (model *pb.DBFactoryDeliveryNote, err error) {
	model = &pb.DBFactoryDeliveryNote{}
	err = postgres.FindOne(comm.TableFactoryDeliveryNote, &model, "factoryid=? and probatch=?", factoryid, probatch)
	return
}

func (this *modelComp) addfactorydeliverynotes(models *pb.DBFactoryDeliveryNote) (err error) {
	err = postgres.Insert(comm.TableFactoryDeliveryNote, models)
	return
}

// 删除指定批次的生产出货单
func (this *modelComp) delfactorydeliverynote(factoryid uint32, productid uint32, probatch uint32) (err error) {
	err = postgres.Delete(comm.TableFactoryDeliveryNote,
		"factoryid=? AND productid=? AND probatch=?", factoryid, productid, probatch)
	return
}

// 统计指定批次中已被使用(status>0 或 uid非空)的设备码数量
func (this *modelComp) countUsedFactoryDevicsByBatch(pid uint32, probatch uint32) (used int64, err error) {
	err = postgres.Table(fmt.Sprintf("%s_%x", comm.TableLicense, pid)).
		Where("probatch=? AND (status>0 OR uid<>'')", probatch).Count(&used).Error
	return
}

// 删除指定批次的全部设备码
func (this *modelComp) delfactoryDevicsByBatch(pid uint32, probatch uint32) (affected int64, err error) {
	tx := postgres.Table(fmt.Sprintf("%s_%x", comm.TableLicense, pid)).
		Where("probatch=?", probatch).Delete(&pb.DBFactoryDevics{})
	affected = tx.RowsAffected
	err = tx.Error
	return
}

// 厂家设备------------------------------
func (this *modelComp) factoryDevics(pid uint32, query interface{}, args ...interface{}) (models []*pb.DBFactoryDevics, err error) {
	models = make([]*pb.DBFactoryDevics, 0)
	err = postgres.Find(fmt.Sprintf("%s_%x", comm.TableLicense, pid), &models, query, args...)
	return
}

// 分页查询授权码（支持 ORDER BY + LIMIT/OFFSET），同时返回命中总数
func (this *modelComp) factoryDevicsPaged(pid uint32, query, orderClause string, limit, offset int, args ...interface{}) (models []*pb.DBFactoryDevics, total int64, err error) {
	models = make([]*pb.DBFactoryDevics, 0)
	tName := fmt.Sprintf("%s_%x", comm.TableLicense, pid)

	tx := postgres.Table(tName)
	if query != "" {
		tx = tx.Where(query, args...)
	}
	if err = tx.Count(&total).Error; err != nil {
		return
	}
	tx2 := postgres.Table(tName)
	if query != "" {
		tx2 = tx2.Where(query, args...)
	}
	if orderClause != "" {
		tx2 = tx2.Order(orderClause)
	}
	if limit > 0 {
		tx2 = tx2.Limit(limit)
	}
	if offset > 0 {
		tx2 = tx2.Offset(offset)
	}
	err = tx2.Find(&models).Error
	return
}

// 批量设置设备码封禁状态（disabled: 0 正常, -1 禁用），返回实际更新条数
func (this *modelComp) setFactoryDevicsDisabled(pid uint32, codes []string, disabled int32) (affected int64, err error) {
	tx := postgres.Table(fmt.Sprintf("%s_%x", comm.TableLicense, pid)).
		Where("code IN ?", codes).Update("disabled", disabled)
	affected = tx.RowsAffected
	err = tx.Error
	return
}

func (this *modelComp) factoryDevic(pid uint32, code string) (model *pb.DBFactoryDevics, err error) {
	model = &pb.DBFactoryDevics{}
	err = postgres.FindOne(fmt.Sprintf("%s_%x", comm.TableLicense, pid), &model, "code=?", code)
	return
}
func (this *modelComp) factoryDevicforuid(pid uint32, uid string) (models []*pb.DBFactoryDevics, err error) {
	models = make([]*pb.DBFactoryDevics, 0)
	err = postgres.Find(fmt.Sprintf("%s_%x", comm.TableLicense, pid), &models, "uid=?", uid)
	return
}
func (this *modelComp) addfactoryDevics(pid uint32, models []*pb.DBFactoryDevics) (err error) {
	// DBFactoryDevics 有 11 列，单条 INSERT 的预编译占位符上限是 65535（MySQL Error 1390）。
	// 6000 行 × 11 列 = 66000 会溢出，这里按 1000 行分批写入。
	err = postgres.Table(fmt.Sprintf("%s_%x", comm.TableLicense, pid)).CreateInBatches(models, 1000).Error
	return
}
func (this *modelComp) updatefactoryDevic(pid uint32, models *pb.DBFactoryDevics) (err error) {
	err = postgres.Save(fmt.Sprintf("%s_%x", comm.TableLicense, pid), &models)
	return
}
func (this *modelComp) updatefactoryDevics(pid uint32, models []*pb.DBFactoryDevics) (err error) {
	err = postgres.Save(fmt.Sprintf("%s_%x", comm.TableLicense, pid), &models)
	return
}

// decrProductStatActivated 将 product_stat.activated_count 原地减 1（下限为 0）。
// 在后台重置设备码（同步删除了对应 userdevice 行）时调用，保证仪表盘数据即时准确，
// 无需等待全量重建统计。
func (this *modelComp) decrProductStatActivated(productid uint32) (err error) {
	err = mysql.Exec(
		"UPDATE "+comm.TableProductStat+
			" SET activated_count = GREATEST(0, activated_count - 1)"+
			" WHERE productid = ?",
		productid,
	).Error
	return
}

// 厂家公码---------------------------------------------------------------------
// 按厂家 + 状态过滤查询公码列表（factoryid=0 不过滤厂家，statusFilter=-1 不过滤状态）
func (this *modelComp) factoryPublicCodes(factoryid uint32, statusFilter int32) (models []*pb.DBFactoryPublicCode, err error) {
	models = make([]*pb.DBFactoryPublicCode, 0)
	tx := postgres.Table(comm.TableFactoryPublicCode)
	if factoryid != 0 {
		tx = tx.Where("factoryid=?", factoryid)
	}
	if statusFilter >= 0 {
		tx = tx.Where("status=?", statusFilter)
	}
	err = tx.Order("createtime DESC").Find(&models).Error
	return
}

func (this *modelComp) factoryPublicCode(code string) (model *pb.DBFactoryPublicCode, err error) {
	model = &pb.DBFactoryPublicCode{}
	err = postgres.FindOne(comm.TableFactoryPublicCode, model, "code=?", code)
	return
}

func (this *modelComp) addFactoryPublicCode(model *pb.DBFactoryPublicCode) (err error) {
	err = postgres.Insert(comm.TableFactoryPublicCode, model)
	return
}

func (this *modelComp) saveFactoryPublicCode(model *pb.DBFactoryPublicCode) (err error) {
	err = postgres.Save(comm.TableFactoryPublicCode, model)
	return
}

func (this *modelComp) delFactoryPublicCode(code string) (err error) {
	err = postgres.Delete(comm.TableFactoryPublicCode, "code=?", code)
	return
}

// 会议记录模板管理---------------------------------------------------------------------
// 列表查询：排除 outline / template 大文本字段，避免传输过大
func (this *modelComp) gettemplates() (models []*pb.DBEchoMeetTemplate, err error) {
	models = make([]*pb.DBEchoMeetTemplate, 0)
	err = postgres.Table(comm.TableEchomeetTemplate).
		Select("id, tid, source, title, description, language, ttype, tags, icon, sort").
		Order("sort DESC").
		Find(&models).Error
	return
}

// 详情查询：返回完整字段（含 outline / template）
func (this *modelComp) gettemplate(id uint64) (model *pb.DBEchoMeetTemplate, err error) {
	model = &pb.DBEchoMeetTemplate{}
	err = postgres.FindOne(comm.TableEchomeetTemplate, &model, "id=?", id)
	return
}

func (this *modelComp) deltemplates(ids []uint64) (err error) {
	err = postgres.Delete(comm.TableEchomeetTemplate, "id IN ?", ids)
	return
}

func (this *modelComp) addtemplates(templates []*pb.DBEchoMeetTemplate) (err error) {
	err = postgres.Insert(comm.TableEchomeetTemplate, templates)
	return
}

func (this *modelComp) updatetemplates(templates []*pb.DBEchoMeetTemplate) (err error) {
	err = postgres.Save(comm.TableEchomeetTemplate, templates)
	return
}

// 支付商品---------------------------------------------------------------------
// 查询支付商品
func (this *modelComp) goodss() (models []*pb.DBGoods, err error) {
	models = make([]*pb.DBGoods, 0)
	err = mysql.Find(comm.TableGoods, &models, "")
	return
}

// 查询支付商品详情
func (this *modelComp) goods(id string) (model *pb.DBGoods, err error) {
	model = &pb.DBGoods{}
	err = mysql.FindOne(comm.TableGoods, &model, "id=?", id)
	return
}

// 添加支付商品
func (this *modelComp) addgoods(product *pb.DBGoods) (err error) {
	err = mysql.Insert(comm.TableGoods, product)
	return
}

// 更新支付商品
func (this *modelComp) updategoods(product *pb.DBGoods) (err error) {
	err = mysql.Save(comm.TableGoods, product)
	return
}

// 删除支付商品
func (this *modelComp) delgoods(id string) (err error) {
	err = mysql.Delete(comm.TableGoods, "id=?", id)
	return
}

// 唤醒词管理---------------------------------------------------------------------
// 查询唤醒语音列表
func (this *modelComp) wakeupvoices() (models []*pb.DBWakeupVoice, err error) {
	models = make([]*pb.DBWakeupVoice, 0)
	err = postgres.Find(comm.TableWakeupVoice, &models, "")
	return
}

// 查询唤醒语音详情
func (this *modelComp) wakeupvoice(id uint32) (model *pb.DBWakeupVoice, err error) {
	model = &pb.DBWakeupVoice{}
	err = postgres.FindOne(comm.TableWakeupVoice, &model, "id=?", id)
	return
}

// 添加唤醒语音
func (this *modelComp) addwakeupvoice(voice *pb.DBWakeupVoice) (err error) {
	err = postgres.Insert(comm.TableWakeupVoice, voice)
	return
}

// 更新唤醒语音
func (this *modelComp) updatewakeupvoice(voice *pb.DBWakeupVoice) (err error) {
	err = postgres.Save(comm.TableWakeupVoice, voice)
	return
}

// 删除唤醒语音
func (this *modelComp) delwakeupvoice(id uint32) (err error) {
	err = postgres.Delete(comm.TableWakeupVoice, "id=?", id)
	return
}

func (this *modelComp) getPayOrders(where string, page, size int32, args ...interface{}) (models []*pb.DBPayOrder, total int64, err error) {
	models = make([]*pb.DBPayOrder, 0)
	tx := mysql.Table(comm.TablePayOrder)
	if where != "" {
		tx = tx.Where(where, args...)
	}
	if err = tx.Count(&total).Error; err != nil {
		this.module.Errorln(err)
		return
	}
	offset := (page - 1) * size
	if offset < 0 {
		offset = 0
	}
	if err = tx.Order("create_time DESC").Offset(int(offset)).Limit(int(size)).Find(&models).Error; err != nil {
		this.module.Errorln(err)
		return
	}
	return
}

// 查询用户会议记录
func (this *modelComp) getUserEchomeetRecords(uid string, start, end int64) (models []*pb.DBEchoMeetRecord, err error) {
	models = make([]*pb.DBEchoMeetRecord, 0)
	where := "uid = ?"
	args := []interface{}{uid}
	if start > 0 {
		where += " AND creationtime >= ?"
		args = append(args, start)
	}
	if end > 0 {
		where += " AND creationtime <= ?"
		args = append(args, end)
	}
	err = mysql.Table(comm.TableEchomeetRecord).
		Omit("original", "translate", "summary").
		Where(where, args...).
		Order("creationtime DESC").
		Find(&models).Error
	return
}

// 查询用户使用量日志
func (this *modelComp) getUserUseLog(query string, args ...interface{}) (models []*pb.DBUserUseLog, err error) {
	models = make([]*pb.DBUserUseLog, 0)
	err = mysql.Find(comm.TableUserUseLog, &models, query, args...)
	return
}

func (this *modelComp) addIntegralLog(log *pb.DBUserUseLog) (err error) {
	err = mysql.Insert(comm.TableUserUseLog, log)
	return
}

// 查询App综合统计（日/月/年）
func (this *modelComp) getAppStats(statType int32, startDate, endDate string) (stats []*pb.DBAppStat, err error) {
	tbl := appstat.TableByType(statType)
	stats = make([]*pb.DBAppStat, 0)
	err = mysql.Find(tbl, &stats, "stat_date >= ? AND stat_date <= ?", startDate, endDate)
	return
}

// 查询全局累计统计（单行）
func (this *modelComp) getGlobalStat() (stat *pb.DBAppStat, err error) {
	stat = &pb.DBAppStat{StatDate: "all"}
	if err = mysql.FindOne(comm.TableAppStatGlobal, stat, "stat_date=?", "all"); err != nil {
		// 不存在则返回空行，不视为错误
		stat = &pb.DBAppStat{StatDate: "all"}
		err = nil
	}
	return
}

// 累计注册人数（用户表 COUNT(*)）
func (this *modelComp) countTotalUsers() (total int64, err error) {
	err = mysql.Table(comm.TableUser).Count(&total).Error
	return
}

// 累计充值人数（付费订单表 COUNT DISTINCT uid, status=已支付）
func (this *modelComp) countTotalPayUsers() (total int64, err error) {
	err = mysql.Table(comm.TablePayOrder).
		Where("status=?", int32(pb.PayOrderStatus_PAY_ORDER_PAID)).
		Distinct("uid").
		Count(&total).Error
	return
}

// agentBatchStats 代理的累计生产批次和设备码总量（delivery notes 维度）
func (this *modelComp) agentBatchStats(factoryIDs, productIDs []uint32) (batchCount, deviceCount int64, err error) {
	type sumResult struct{ Total int64 }
	var cond string
	var args []interface{}
	if len(factoryIDs) > 0 && len(productIDs) > 0 {
		cond = "factoryid IN ? OR productid IN ?"
		args = []interface{}{factoryIDs, productIDs}
	} else if len(factoryIDs) > 0 {
		cond = "factoryid IN ?"
		args = []interface{}{factoryIDs}
	} else if len(productIDs) > 0 {
		cond = "productid IN ?"
		args = []interface{}{productIDs}
	}
	txCount := postgres.Table(comm.TableFactoryDeliveryNote)
	txSum := postgres.Table(comm.TableFactoryDeliveryNote)
	if cond != "" {
		txCount = txCount.Where(cond, args...)
		txSum = txSum.Where(cond, args...)
	}
	if err = txCount.Count(&batchCount).Error; err != nil {
		return
	}
	var r sumResult
	if err = txSum.Select("COALESCE(SUM(devicetnum), 0) as total").Scan(&r).Error; err != nil {
		return
	}
	deviceCount = r.Total
	return
}

// agentDeviceUIDs 返回绑定了指定产品设备的去重用户 uid 列表。
// 按 ServiceDB 的 userdevice 表实时统计（per-后台口径），不读共享 AdminDB 的 license 分表，
// 供充值 / 消耗统计按用户聚合使用。
// 注：激活数 / 绑定用户数的展示值改读 product_stat 快照（见 sumProductStats）。
func (this *modelComp) agentDeviceUIDs(productIDs []uint32) (uids []string, err error) {
	uids = make([]string, 0)
	if len(productIDs) == 0 {
		return
	}
	err = mysql.Table(comm.TableUserdevice).
		Where("productid IN ? AND uid != ''", productIDs).
		Distinct("uid").Pluck("uid", &uids).Error
	return
}

// sumProductStats 读取 product_stat 快照，汇总指定产品的激活设备数与绑定用户数。
// product_stat 由「重建统计」时全量扫描 userdevice 落库（见 rebuildProductStats）。
// 注：bound_user_count 为各产品独立去重值，跨产品求和时同时绑定多产品的用户会被重复计数；
// 单产品（仪表盘按 product_id 查看）口径精确。
func (this *modelComp) sumProductStats(productIDs []uint32) (activatedCount, boundUserCount int64, err error) {
	if len(productIDs) == 0 {
		return
	}
	type row struct {
		Activated int64 `gorm:"column:activated"`
		Bound     int64 `gorm:"column:bound"`
	}
	var r row
	err = mysql.Table(comm.TableProductStat).
		Select("COALESCE(SUM(activated_count),0) AS activated, COALESCE(SUM(bound_user_count),0) AS bound").
		Where("productid IN ?", productIDs).Scan(&r).Error
	activatedCount, boundUserCount = r.Activated, r.Bound
	return
}

// agentPayStats 代理用户的充值订单数和累计金额
func (this *modelComp) agentPayStats(uids []string) (orderCount, totalAmount int64, err error) {
	if len(uids) == 0 {
		return
	}
	type sumResult struct{ Total int64 }
	paid := int32(pb.PayOrderStatus_PAY_ORDER_PAID)
	if err = mysql.Table(comm.TablePayOrder).
		Where("uid IN ? AND status = ?", uids, paid).Count(&orderCount).Error; err != nil {
		return
	}
	var r sumResult
	if err = mysql.Table(comm.TablePayOrder).
		Where("uid IN ? AND status = ?", uids, paid).
		Select("COALESCE(SUM(amount), 0) as total").Scan(&r).Error; err != nil {
		return
	}
	totalAmount = r.Total
	return
}

// userstatistics 表实际列名（gorm 默认命名策略将 Trademodel1Time 转为 trademodel1_time）
const (
	colTradeTimeSum = "IFNULL(trademodel1_time,0)+IFNULL(trademodel2_time,0)+IFNULL(trademodel3_time,0)+IFNULL(trademodel4_time,0)"
	colTradeNumSum  = "IFNULL(trademodel1_num,0)+IFNULL(trademodel2_num,0)+IFNULL(trademodel3_num,0)+IFNULL(trademodel4_num,0)"
)

// agentUsageStats 名下用户累计翻译/会议消耗汇总。uids 为空返回 0。
func (this *modelComp) agentUsageStats(uids []string) (tradeTime, tradeCount, meetTime, meetCount int64, err error) {
	if len(uids) == 0 {
		return
	}
	type sumRow struct {
		TradeTime  int64 `gorm:"column:trade_time"`
		TradeCount int64 `gorm:"column:trade_count"`
		MeetTime   int64 `gorm:"column:meet_time"`
		MeetCount  int64 `gorm:"column:meet_count"`
	}
	var r sumRow
	err = mysql.Table(comm.TableUserStatistics).
		Select("COALESCE(SUM("+colTradeTimeSum+"),0) AS trade_time, "+
			"COALESCE(SUM("+colTradeNumSum+"),0) AS trade_count, "+
			"COALESCE(SUM(meettime),0) AS meet_time, "+
			"COALESCE(SUM(meetnum),0) AS meet_count").
		Where("uid IN ?", uids).Scan(&r).Error
	if err != nil {
		return
	}
	tradeTime, tradeCount, meetTime, meetCount = r.TradeTime, r.TradeCount, r.MeetTime, r.MeetCount
	return
}

// userRankRow 排行榜单行原始数据（不含 user 信息，需另查 user 表填充）
type userRankRow struct {
	Uid        string `gorm:"column:uid"`
	TradeTime  int64  `gorm:"column:trade_time"`
	TradeCount int64  `gorm:"column:trade_count"`
	MeetTime   int64  `gorm:"column:meet_time"`
	MeetCount  int64  `gorm:"column:meet_count"`
}

// topUserRankByTrade 按翻译总时长降序取 Top N（4 个翻译模式时长合计）
func (this *modelComp) topUserRankByTrade(limit int) (rows []*userRankRow, err error) {
	rows = make([]*userRankRow, 0)
	err = mysql.Table(comm.TableUserStatistics).
		Select("uid, (" + colTradeTimeSum + ") AS trade_time, (" + colTradeNumSum + ") AS trade_count, IFNULL(meettime,0) AS meet_time, IFNULL(meetnum,0) AS meet_count").
		Where("(" + colTradeTimeSum + ") > 0").
		Order("trade_time DESC").
		Limit(limit).
		Scan(&rows).Error
	return
}

// topUserRankByMeet 按会议时长降序取 Top N
func (this *modelComp) topUserRankByMeet(limit int) (rows []*userRankRow, err error) {
	rows = make([]*userRankRow, 0)
	err = mysql.Table(comm.TableUserStatistics).
		Select("uid, (" + colTradeTimeSum + ") AS trade_time, (" + colTradeNumSum + ") AS trade_count, IFNULL(meettime,0) AS meet_time, IFNULL(meetnum,0) AS meet_count").
		Where("IFNULL(meettime,0) > 0").
		Order("meet_time DESC").
		Limit(limit).
		Scan(&rows).Error
	return
}

// findUsersByUids 批量查 user 表，返回 uid -> DBUser
func (this *modelComp) findUsersByUids(uids []string) (m map[string]*pb.DBUser, err error) {
	m = make(map[string]*pb.DBUser, len(uids))
	if len(uids) == 0 {
		return
	}
	var users []*pb.DBUser
	if err = mysql.Table(comm.TableUser).Where("uid IN ?", uids).Find(&users).Error; err != nil {
		return
	}
	for _, u := range users {
		m[u.Uid] = u
	}
	return
}

// addAdminResourceLog 写入超管→后台账号 的资源点流水
func (this *modelComp) addAdminResourceLog(log *pb.DBAdminResourceLog) (err error) {
	err = mysql.Insert(comm.TableAdminResLog, log)
	return
}

// getAdminResourceLogs 查询资源流水（按账号 + 分页）
func (this *modelComp) getAdminResourceLogs(account string, page, size int32) (logs []*pb.DBAdminResourceLog, total int64, err error) {
	logs = make([]*pb.DBAdminResourceLog, 0)
	tx := mysql.Table(comm.TableAdminResLog)
	if account != "" {
		tx = tx.Where("from_account=? OR to_account=?", account, account)
	}
	if err = tx.Count(&total).Error; err != nil {
		return
	}
	if size <= 0 {
		size = 20
	}
	if page <= 0 {
		page = 1
	}
	offset := (page - 1) * size
	err = tx.Order("ts DESC").Offset(int(offset)).Limit(int(size)).Find(&logs).Error
	return
}

// sumAdminResourceFlow 汇总某账号的累计接收/派发量（vipday/aichat/trade-sec/meet-sec）
// 接收: to_account=account 的 SUM
// 派发: extra=account 的 useruselog SUM（即名下用户被赠送的）
func (this *modelComp) sumAdminReceivedResource(account string) (vipday, aichat, tradesec, meetsec int64, err error) {
	type row struct {
		Vipday   int64 `gorm:"column:vipday"`
		Aichat   int64 `gorm:"column:aichat"`
		Tradesec int64 `gorm:"column:tradesec"`
		Meetsec  int64 `gorm:"column:meetsec"`
	}
	var r row
	err = mysql.Table(comm.TableAdminResLog).
		Select("COALESCE(SUM(vipday),0) AS vipday, COALESCE(SUM(aichatintegral),0) AS aichat, "+
			"COALESCE(SUM(tradesecond),0) AS tradesec, COALESCE(SUM(meetsecond),0) AS meetsec").
		Where("to_account=?", account).Scan(&r).Error
	if err != nil {
		return
	}
	vipday, aichat, tradesec, meetsec = r.Vipday, r.Aichat, r.Tradesec, r.Meetsec
	return
}

func (this *modelComp) sumAdminDispatchedResource(account string) (vipday, aichat, tradesec, meetsec int64, err error) {
	type row struct {
		Vipday   int64 `gorm:"column:vipday"`
		Aichat   int64 `gorm:"column:aichat"`
		Tradesec int64 `gorm:"column:tradesec"`
		Meetsec  int64 `gorm:"column:meetsec"`
	}
	var r row
	// 注意：DBUserUseLog.Addvipday 的 gorm tag 写法 `gorm:"viptime"` 不是有效的自定义列名语法
	// （正确应为 `gorm:"column:viptime"`），GORM 会忽略该 tag 并按默认命名策略，
	// 表中实际列名为 addvipday；此处以实际列名为准。
	err = mysql.Table(comm.TableUserUseLog).
		Select("COALESCE(SUM(addvipday),0) AS vipday, COALESCE(SUM(addagentintegral),0) AS aichat, "+
			"COALESCE(SUM(addtradesecond),0) AS tradesec, COALESCE(SUM(addmeetsecond),0) AS meetsec").
		Where("logtype=? AND extra=?", int32(pb.UserLogType_AdminGive), account).Scan(&r).Error
	if err != nil {
		return
	}
	vipday, aichat, tradesec, meetsec = r.Vipday, r.Aichat, r.Tradesec, r.Meetsec
	return
}

// getUserUseLogsPaged 用户使用量日志分页查询（流水）
// operator 非空时按 extra=operator 过滤（仅 AdminGive 类型的 extra 是操作人账号）
func (this *modelComp) getUserUseLogsPaged(uid string, logtype pb.UserLogType, operator string, page, size int32) (logs []*pb.DBUserUseLog, total int64, err error) {
	logs = make([]*pb.DBUserUseLog, 0)
	tx := mysql.Table(comm.TableUserUseLog)
	if uid != "" {
		tx = tx.Where("uid=?", uid)
	}
	if logtype != pb.UserLogType_UserLogTypeUnknown {
		tx = tx.Where("logtype=?", int32(logtype))
	}
	if operator != "" {
		tx = tx.Where("extra=?", operator)
	}
	if err = tx.Count(&total).Error; err != nil {
		return
	}
	if size <= 0 {
		size = 10
	}
	if page <= 0 {
		page = 1
	}
	offset := (page - 1) * size
	err = tx.Order("ts DESC").Offset(int(offset)).Limit(int(size)).Find(&logs).Error
	return
}
