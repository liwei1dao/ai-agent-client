package postgres

import "gorm.io/gorm"

/*
系统描述:PostgreSQL 数据库驱动系统（与 lego/sys/mysql 平级，实现同一套 DB 抽象）
*/
type (
	ISys interface {
		Table(tName string) (tx *gorm.DB)
		Begin() (tx *gorm.DB)
		Raw(sql string, values ...interface{}) (tx *gorm.DB)
		Exec(sql string, values ...interface{}) (tx *gorm.DB)
		CreateTable(tName string, model any) (err error)
		AutoIncrementStart(tName, column string, start uint64) (err error)
		FindOne(tName string, model any, query interface{}, args ...interface{}) (err error)
		// FindOnePrimary 与 FindOne 相同，但强制走主库（绕过只读副本）。
		// 用于"读后写同一行"等强一致场景，避免读到复制延迟内的旧数据。未配置副本时与 FindOne 等价。
		FindOnePrimary(tName string, model any, query interface{}, args ...interface{}) (err error)
		Find(tName string, models any, query interface{}, args ...interface{}) (err error)
		Insert(tName string, model any) (err error)
		Save(tName string, model any) (err error)
		Delete(tName string, query interface{}, args ...interface{}) (err error)
		DropTable(tName string) (err error)
	}
)

var (
	defsys         ISys
	ErrNoDocuments = gorm.ErrRecordNotFound
)

func OnInit(config map[string]interface{}, option ...Option) (err error) {
	defsys, err = newSys(newOptions(config, option...))
	return
}

func NewSys(option ...Option) (sys ISys, err error) {
	sys, err = newSys(newOptionsByOption(option...))
	return
}

// GetSys 返回全局 postgres 实例（需要 ISys 全部方法时用，如 Save/Begin/AutoIncrementStart）。
func GetSys() ISys {
	return defsys
}

func Table(tName string) (tx *gorm.DB) {
	return defsys.Table(tName)
}
func Exec(sql string, values ...interface{}) (tx *gorm.DB) {
	return defsys.Exec(sql, values...)
}
func Raw(sql string, values ...interface{}) (tx *gorm.DB) {
	return defsys.Raw(sql, values...)
}
func CreateTable(tName string, model any) (err error) {
	return defsys.CreateTable(tName, model)
}
func FindOne(tName string, model any, query interface{}, args ...interface{}) (err error) {
	return defsys.FindOne(tName, model, query, args...)
}
func Find(tName string, models any, query interface{}, args ...interface{}) (err error) {
	return defsys.Find(tName, models, query, args...)
}
func Insert(tName string, model any) (err error) {
	return defsys.Insert(tName, model)
}

func Save(tName string, model any) (err error) {
	return defsys.Save(tName, model)
}

func FindOnePrimary(tName string, model any, query interface{}, args ...interface{}) (err error) {
	return defsys.FindOnePrimary(tName, model, query, args...)
}

func AutoIncrementStart(tName, column string, start uint64) (err error) {
	return defsys.AutoIncrementStart(tName, column, start)
}

func Delete(tName string, query interface{}, args ...interface{}) (err error) {
	return defsys.Delete(tName, query, args...)
}

func DropTable(tName string) (err error) {
	return defsys.DropTable(tName)
}
