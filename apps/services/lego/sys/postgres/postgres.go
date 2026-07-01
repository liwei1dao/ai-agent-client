package postgres

import (
	"strings"
	"sync"
	"time"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/plugin/dbresolver"
)

func newSys(options Options) (sys *Postgres, err error) {
	sys = &Postgres{options: options}
	err = sys.init()
	return
}

// withExecQueryMode 确保 DSN 带 default_query_exec_mode=cache_describe。
//
// 为什么是 cache_describe 而不是 exec/simple_protocol：
//   - 用匿名 prepared statement（不保留命名语句），故兼容 Supabase 6543 事务模式连接池；
//   - 会向服务端 Describe 拿到参数 OID（如 int4），据此把 Go 值按目标列类型编码——
//     protobuf 枚举(命名 int32)因此被正确编码成整数；
//   - Describe 结果带缓存，避免每次查询多一次往返。
//
// 反例：exec 模式不 Describe、只按 Go 类型猜，对"命名 int32 + 带 Stringer"的枚举会退化成
// 文本走 Stringer，把枚举编成名字(如 "Admin")，integer 列报 22P02；simple_protocol 同病。
// 该参数是 pgx 私有的，由 pgx.ParseConfig 消费、不会发给 PostgreSQL 服务端。
func withExecQueryMode(dsn string) string {
	if strings.Contains(dsn, "default_query_exec_mode") {
		return dsn
	}
	sep := "?"
	if strings.Contains(dsn, "?") {
		sep = "&"
	}
	return dsn + sep + "default_query_exec_mode=cache_describe"
}

// ——— 连接池硬保护 ———
// Supabase pooler 的 max_client_conn 是全项目共享的硬上限（Small 规格固定 400），
// 单进程池必须严格受控：绝不允许"无限制"或"大量空闲"连接，否则极易把全项目额度打满。
// 这些常量是兜底保护，无论上层配置怎么填都不会被突破。
const (
	defaultMaxOpenConns = 5                // 未配置或配置非法(<=0)时的保守默认
	maxAllowedOpenConns = 10               // 硬上限：即便配置写大，也强制夹到这里
	hardMaxIdleConns    = 1                // 最多保留 1 条空闲连接，杜绝大量空闲堆积
	poolConnMaxIdleTime = 30 * time.Second // 空闲超 30s 立即回收，连接尽快还给 pooler
	poolConnMaxLifetime = 30 * time.Minute // 连接最长存活，定期重建避免老连接
)

type Postgres struct {
	options  Options
	db       *gorm.DB
	mu       sync.Mutex
	existing map[string]bool //已存在表缓存，避免每张表都向远端探测
}

// safePoolSize 把配置的池大小夹到 [1, maxAllowedOpenConns]。
// 关键保护：绝不返回 0——database/sql 里 SetMaxOpenConns(0) 等于"无限制"，
// 是把 Supabase pooler 打满的最大隐患；配置为 0/负数一律回落到保守默认值。
func (this *Postgres) safePoolSize() int {
	n := int(this.options.MaxPoolSize)
	if n <= 0 {
		this.options.Log.Errorf("postgres MaxPoolSize=%d 非法(<=0)，已回落默认 %d（SetMaxOpenConns(0) 会变无限制，必须兜底）", this.options.MaxPoolSize, defaultMaxOpenConns)
		n = defaultMaxOpenConns
	}
	if n > maxAllowedOpenConns {
		this.options.Log.Errorf("postgres MaxPoolSize=%d 超出硬上限 %d，已强制夹到 %d（防止单进程吃光全项目连接额度）", this.options.MaxPoolSize, maxAllowedOpenConns, maxAllowedOpenConns)
		n = maxAllowedOpenConns
	}
	return n
}

func (this *Postgres) init() (err error) {
	// 走 pgx cache_describe 模式（由 withExecQueryMode 注入 default_query_exec_mode=cache_describe）：
	// 用匿名 prepared statement，故可对接 Supabase 6543 事务模式连接池。详见 withExecQueryMode 注释。
	// DSN 端口请用 6543（事务模式）。
	// 连接失败直接返回错误，不重试——由上层决定如何处理。
	if this.db, err = gorm.Open(postgres.Open(withExecQueryMode(this.options.Dsn)), &gorm.Config{}); err != nil {
		this.options.Log.Errorf("connect postgres failed: %v", err)
		return
	}
	// 连接池硬保护：开连接数受 safePoolSize 夹取(永不为 0/无限制)，空闲连接 ≤1、空闲超 30s 立即回收，
	// 保证单进程绝不出现"大量空闲连接"长期占用全项目共享的 max_client_conn 额度。
	maxOpen := this.safePoolSize()
	maxIdle := hardMaxIdleConns
	if maxIdle > maxOpen {
		maxIdle = maxOpen
	}
	if sqlDB, e := this.db.DB(); e == nil {
		sqlDB.SetMaxOpenConns(maxOpen)
		sqlDB.SetMaxIdleConns(maxIdle)
		sqlDB.SetConnMaxIdleTime(poolConnMaxIdleTime)
		sqlDB.SetConnMaxLifetime(poolConnMaxLifetime)
	}
	// 读写分离：配了只读副本 DSN 就挂 dbresolver——
	//   读(SELECT: FindOne/Find/Raw) 自动走副本，写(Insert/Save/Update/Delete/Exec)与 DDL/事务 走主库。
	//   副本同样是 Supabase 6543 事务池，需注入 cache_describe，并设同样保守的小连接池。
	//   读后写同一行等强一致场景请用 FindOnePrimary 强制回主库（绕开复制延迟）。
	if this.options.ReadDsn != "" {
		resolver := dbresolver.Register(dbresolver.Config{
			Replicas: []gorm.Dialector{postgres.Open(withExecQueryMode(this.options.ReadDsn))},
			Policy:   dbresolver.RandomPolicy{},
		}).
			SetMaxOpenConns(maxOpen).
			SetMaxIdleConns(maxIdle).
			SetConnMaxIdleTime(poolConnMaxIdleTime).
			SetConnMaxLifetime(poolConnMaxLifetime)
		if e := this.db.Use(resolver); e != nil {
			// 注册失败不致命：退回单库（主库），仅记录错误。
			this.options.Log.Errorf("register read replica failed, fallback to single db: %v", e)
		} else {
			this.options.Log.Infof("postgres read replica enabled")
		}
	}
	return
}

func (this *Postgres) Exec(sql string, values ...interface{}) (tx *gorm.DB) {
	return this.db.Exec(sql, values...)
}

func (this *Postgres) Raw(sql string, values ...interface{}) (tx *gorm.DB) {
	return this.db.Raw(sql, values...)
}

// loadExisting 一次性把当前 schema 下已有表名加载进缓存（懒加载，仅首次发一条查询）。
func (this *Postgres) loadExisting() (err error) {
	this.mu.Lock()
	defer this.mu.Unlock()
	if this.existing != nil {
		return
	}
	var names []string
	if err = this.db.Raw(`SELECT tablename FROM pg_tables WHERE schemaname = CURRENT_SCHEMA()`).Scan(&names).Error; err != nil {
		return
	}
	this.existing = make(map[string]bool, len(names))
	for _, n := range names {
		this.existing[n] = true
	}
	return
}

// CreateTable 建表。表已存在则跳过 AutoMigrate —— AutoMigrate 会对每张表发数十条 schema 探测查询，
// 在远端高延迟(如跨洋 Supabase)下会让启动慢到几分钟。表结构已由迁移工具建好；
// 后续 schema 变更请走迁移工具/手动 DDL，而非依赖每次启动 AutoMigrate。
func (this *Postgres) CreateTable(tName string, model any) (err error) {
	if err = this.loadExisting(); err != nil {
		return
	}
	this.mu.Lock()
	exists := this.existing[tName]
	this.mu.Unlock()
	if exists {
		return
	}
	if err = this.db.Table(tName).AutoMigrate(model); err != nil {
		return
	}
	this.mu.Lock()
	this.existing[tName] = true
	this.mu.Unlock()
	return
}

// AutoIncrementStart 设置表自增主键起始值。
// 仅当表为空时把序列重置到 start，避免覆盖线上已有的序列位置。
func (this *Postgres) AutoIncrementStart(tName, column string, start uint64) (err error) {
	var n int64
	if err = this.db.Table(tName).Count(&n).Error; err != nil {
		return
	}
	if n > 0 {
		return // 已有数据，保持现有序列不动
	}
	// setval(seq, start, false) 使下一个 nextval 恰好等于 start
	err = this.db.Exec(`SELECT setval(pg_get_serial_sequence(?, ?), ?, false)`,
		tName, column, start).Error
	return
}

// 获取表对象
func (this *Postgres) Table(tName string) (tx *gorm.DB) {
	return this.db.Table(tName)
}

// 查询数据
func (this *Postgres) FindOne(tName string, model any, query interface{}, args ...interface{}) (err error) {
	result := this.db.Table(tName).Where(query, args...).First(model)
	if result.Error != nil {
		err = result.Error
	}
	return
}

// FindOnePrimary 强制走主库（dbresolver.Write）。用于"读后写同一行"等强一致场景，
// 避免读到只读副本的复制延迟旧数据。未注册副本时该 Clause 被忽略，行为等同 FindOne。
func (this *Postgres) FindOnePrimary(tName string, model any, query interface{}, args ...interface{}) (err error) {
	result := this.db.Clauses(dbresolver.Write).Table(tName).Where(query, args...).First(model)
	if result.Error != nil {
		err = result.Error
	}
	return
}

// 查询数据
func (this *Postgres) Find(tName string, models any, query interface{}, args ...interface{}) (err error) {
	result := this.db.Table(tName).Where(query, args...).Find(models)
	if result.Error != nil {
		err = result.Error
	}
	return
}

// 插入数据
func (this *Postgres) Insert(tName string, model any) (err error) {
	result := this.db.Table(tName).Create(model)
	if result.Error != nil {
		err = result.Error
	}
	return
}

// 更新指定字段
func (this *Postgres) Update(tName string, where, change map[string]interface{}) (err error) {
	result := this.db.Table(tName).Where(where).Updates(change)
	if result.Error != nil {
		err = result.Error
	}
	return
}

func (this *Postgres) Save(tName string, model any) (err error) {
	err = this.db.Table(tName).Save(model).Error
	return
}

// 删除数据
func (this *Postgres) Delete(tName string, query interface{}, args ...interface{}) (err error) {
	result := this.db.Table(tName).Where(query, args...).Unscoped().Delete(nil)
	if result.Error != nil {
		err = result.Error
	}
	return
}

// 删除表
func (this *Postgres) DropTable(tName string) (err error) {
	return this.db.Migrator().DropTable(tName)
}

// 事务
func (this *Postgres) Begin() (tx *gorm.DB) {
	return this.db.Begin()
}
