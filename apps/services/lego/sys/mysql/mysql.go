package mysql

import (
	"fmt"

	"gorm.io/driver/mysql"
	"gorm.io/gorm"
)

func newSys(options Options) (sys *MySql, err error) {
	sys = &MySql{options: options}
	err = sys.init()
	return
}

type MySql struct {
	options Options
	db      *gorm.DB
}

func (this *MySql) init() (err error) {
	this.db, err = gorm.Open(mysql.Open(this.options.MySQLDsn), &gorm.Config{})
	if err != nil {
		this.options.Log.Errorln(err)
	}
	return
}

// AutoIncrementStart 设置表自增主键的起始值（MySQL: ALTER TABLE ... AUTO_INCREMENT）。
// column 仅为跨驱动接口对齐保留，MySQL 用表级设置无需列名。
func (this *MySql) AutoIncrementStart(tName, column string, start uint64) (err error) {
	_ = column
	err = this.db.Exec(fmt.Sprintf("ALTER TABLE %s AUTO_INCREMENT = %d", tName, start)).Error
	return
}

func (this *MySql) Exec(sql string, values ...interface{}) (tx *gorm.DB) {
	tx = this.db.Exec(sql, values...)
	return
}

func (this *MySql) Raw(sql string, values ...interface{}) (tx *gorm.DB) {
	tx = this.db.Raw(sql, values...)
	return
}

func (this *MySql) CreateTable(tName string, model any) (err error) {
	err = this.db.Table(tName).AutoMigrate(model)
	return
}

// 获取表对象
func (this *MySql) Table(tName string) (tx *gorm.DB) {
	tx = this.db.Table(tName)
	return
}

// 查询数据
func (this *MySql) FindOne(tName string, model any, query interface{}, args ...interface{}) (err error) {
	result := this.db.Table(tName).Where(query, args...).First(model)
	if result.Error != nil {
		err = result.Error
	}
	return
}

// FindOnePrimary MySQL 未做读写分离，等同 FindOne（仅为与 postgres 驱动接口对齐）。
func (this *MySql) FindOnePrimary(tName string, model any, query interface{}, args ...interface{}) (err error) {
	return this.FindOne(tName, model, query, args...)
}

// 查询数据
func (this *MySql) Find(tName string, models any, query interface{}, args ...interface{}) (err error) {
	result := this.db.Table(tName).Where(query, args...).Find(models)
	if result.Error != nil {
		err = result.Error
	}
	return
}

// 插入数据
func (this *MySql) Insert(tName string, model any) (err error) {
	result := this.db.Table(tName).Create(model)
	if result.Error != nil {
		err = result.Error
	}
	return
}

// 插入数据
func (this *MySql) Update(tName string, where, change map[string]interface{}) (err error) {
	// 使用 Update 方法更新特定字段
	result := this.db.Table(tName).Where(where).Updates(change)
	if result.Error != nil {
		err = result.Error
	}
	return
}

func (this *MySql) Save(tName string, model any) (err error) {
	err = this.db.Table(tName).Save(model).Error
	return
}

// 插入数据
func (this *MySql) Delete(tName string, query interface{}, args ...interface{}) (err error) {
	// 使用 Update 方法更新特定字段
	result := this.db.Table(tName).Where(query, args...).Unscoped().Delete(nil)
	if result.Error != nil {
		err = result.Error
	}
	return
}

// 删除表
func (this *MySql) DropTable(tName string) (err error) {
	// 使用 Update 方法更新特定字段
	err = this.db.Migrator().DropTable(tName)
	return
}

// 事务
func (this *MySql) Begin() (tx *gorm.DB) {
	tx = this.db.Begin()
	return
}
