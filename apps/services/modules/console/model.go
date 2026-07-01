package console

import (
	"time"

	"yunyan/comm"
	"yunyan/lego/core"
	"yunyan/lego/core/cbase"
	"yunyan/lego/sys/postgres"
)

// console 自有表名。third_svc_config 为 console 专属（api 模块不建），其余加 console_ 前缀，
// 避免与 modules/api 在同一 Postgres 上的 agent / mcp / global_config 表（pb schema）冲突。
const (
	tableSvcConfig    = comm.TableThirdSvcConfig // "third_svc_config"
	tableAgent        = "console_agent"
	tableMcp          = "console_mcp"
	tableGlobalConfig = "console_global_config"
)

/* ---------------- 数据模型（gorm + json，字段对齐 apps/admin） ---------------- */

// SvcField 服务字段定义（fields[]）。
type SvcField struct {
	Key         string `json:"key"`
	Description string `json:"description"`
	Encrypted   bool   `json:"encrypted"`
	DefValue    string `json:"def_value"`
	Sort        int    `json:"sort"`
}

// SvcConfig 第三方服务配置（third_svc_config）。
type SvcConfig struct {
	Id          string     `json:"id" gorm:"primaryKey;column:id"`
	Name        string     `json:"name"`
	Categories  string     `json:"categories"` // 逗号分隔：1=LLM 2=STT 3=TTS 4=AST 5=STS 6=MT
	Description string     `json:"description"`
	Enable      bool       `json:"enable"`
	Fields      []SvcField `json:"fields" gorm:"serializer:json"`
	Createtime  int64      `json:"createtime"`
	Updatetime  int64      `json:"updatetime"`
}

func (SvcConfig) TableName() string { return tableSvcConfig }

// AgentVariable Agent 变量定义（variables[]）。
type AgentVariable struct {
	Name         string `json:"name"`
	Type         string `json:"type"`
	Required     bool   `json:"required"`
	DefaultValue string `json:"default_value"`
	Description  string `json:"description"`
}

// Agent 智能体配置（DBVoitransAgent 的可落库版本）。
type Agent struct {
	AgentId            string          `json:"agent_id" gorm:"primaryKey;column:agent_id"`
	Name               string          `json:"name"`
	Type               string          `json:"type"` // agent_chat / agent_sts_chat / agent_translate / agent_ast_translate
	Description        string          `json:"description"`
	AvatarUrl          string          `json:"avatar_url"`
	SupportedLanguages []string        `json:"supported_languages" gorm:"serializer:json"`
	Variables          []AgentVariable `json:"variables" gorm:"serializer:json"`
	Enable             bool            `json:"enable"`
	LlmSvcId           string          `json:"llm_svc_id"`
	TtsSvcId           string          `json:"tts_svc_id"`
	Createtime         int64           `json:"createtime"`
	Updatetime         int64           `json:"updatetime"`
}

func (Agent) TableName() string { return tableAgent }

// McpServer MCP 工具服务（mcp_server）。
type McpServer struct {
	Id         string `json:"id" gorm:"primaryKey;column:id"`
	Name       string `json:"name"`
	Transport  string `json:"transport"` // sse / stdio
	Endpoint   string `json:"endpoint"`
	Enable     bool   `json:"enable"`
	ToolCount  int    `json:"tool_count"`
	Updatetime int64  `json:"updatetime"`
}

func (McpServer) TableName() string { return tableMcp }

// GlobalConfigItem 全局键值配置（group/key/value 为 SQL 敏感词，列名加后缀）。
type GlobalConfigItem struct {
	Id          uint64 `json:"id" gorm:"primaryKey;autoIncrement"`
	Group       string `json:"group" gorm:"column:group_name"`
	Key         string `json:"key" gorm:"column:config_key"`
	Value       string `json:"value" gorm:"column:config_value"`
	Type        string `json:"type"` // string / number / bool
	Description string `json:"description"`
}

func (GlobalConfigItem) TableName() string { return tableGlobalConfig }

/* ---------------- 组件 ---------------- */

type modelComp struct {
	cbase.ModuleCompBase
	module *Console
}

func (this *modelComp) Init(service core.IService, module core.IModule, comp core.IModuleComp, opt core.IModuleOptions) (err error) {
	this.ModuleCompBase.Init(service, module, comp, opt)
	this.module = module.(*Console)
	for _, m := range []any{&SvcConfig{}, &Agent{}, &McpServer{}, &GlobalConfigItem{}} {
		if e := postgres.CreateTable(tableNameOf(m), m); e != nil {
			this.module.Errorln(e)
		}
	}
	return
}

func tableNameOf(m any) string {
	if t, ok := m.(interface{ TableName() string }); ok {
		return t.TableName()
	}
	return ""
}

/* ---- 服务配置 ---- */
func (this *modelComp) svcConfigs() (list []*SvcConfig, err error) {
	list = make([]*SvcConfig, 0)
	err = postgres.Find(tableSvcConfig, &list, "")
	return
}
func (this *modelComp) saveSvcConfig(m *SvcConfig) error {
	now := time.Now().Unix()
	if m.Createtime == 0 {
		m.Createtime = now
	}
	m.Updatetime = now
	return postgres.Save(tableSvcConfig, m)
}
func (this *modelComp) delSvcConfig(id string) error {
	return postgres.Delete(tableSvcConfig, "id=?", id)
}

/* ---- Agent ---- */
func (this *modelComp) agents() (list []*Agent, err error) {
	list = make([]*Agent, 0)
	err = postgres.Find(tableAgent, &list, "")
	return
}
func (this *modelComp) saveAgent(m *Agent) error {
	now := time.Now().Unix()
	if m.Createtime == 0 {
		m.Createtime = now
	}
	m.Updatetime = now
	return postgres.Save(tableAgent, m)
}
func (this *modelComp) delAgent(id string) error {
	return postgres.Delete(tableAgent, "agent_id=?", id)
}

/* ---- MCP ---- */
func (this *modelComp) mcpServers() (list []*McpServer, err error) {
	list = make([]*McpServer, 0)
	err = postgres.Find(tableMcp, &list, "")
	return
}
func (this *modelComp) saveMcpServer(m *McpServer) error {
	m.Updatetime = time.Now().Unix()
	return postgres.Save(tableMcp, m)
}
func (this *modelComp) delMcpServer(id string) error {
	return postgres.Delete(tableMcp, "id=?", id)
}

/* ---- 全局配置 ---- */
func (this *modelComp) globalConfigs() (list []*GlobalConfigItem, err error) {
	list = make([]*GlobalConfigItem, 0)
	err = postgres.Find(tableGlobalConfig, &list, "")
	return
}
func (this *modelComp) saveGlobalConfig(m *GlobalConfigItem) error {
	return postgres.Save(tableGlobalConfig, m)
}
func (this *modelComp) delGlobalConfig(id uint64) error {
	return postgres.Delete(tableGlobalConfig, "id=?", id)
}
