package configcenter

import (
	"yunyan/lego/core"
	"yunyan/lego/core/cbase"
	"yunyan/lego/sys/postgres"
)

// 读 console 写入的表（配置中心只读）。
const (
	tableSvcConfig    = "third_svc_config"
	tableAgent        = "console_agent"
	tableMcp          = "console_mcp"
	tableGlobalConfig = "console_global_config"
)

/* ---------------- 下发视图（json 标签即客户端解密后看到的字段） ---------------- */

type svcField struct {
	Key         string `json:"key"`
	Description string `json:"description"`
	Encrypted   bool   `json:"encrypted"`
	DefValue    string `json:"def_value"`
	Sort        int    `json:"sort"`
}

type svcConfig struct {
	Id          string     `json:"id" gorm:"column:id"`
	Name        string     `json:"name"`
	Categories  string     `json:"categories"`
	Description string     `json:"description"`
	Enable      bool       `json:"-"`
	Fields      []svcField `json:"fields" gorm:"serializer:json"`
}

func (svcConfig) TableName() string { return tableSvcConfig }

type agentVar struct {
	Name         string `json:"name"`
	Type         string `json:"type"`
	Required     bool   `json:"required"`
	DefaultValue string `json:"default_value"`
	Description  string `json:"description"`
}

type agentConfig struct {
	AgentId            string     `json:"agent_id" gorm:"column:agent_id"`
	Name               string     `json:"name"`
	Type               string     `json:"type"`
	Description        string     `json:"description"`
	AvatarUrl          string     `json:"avatar_url" gorm:"column:avatar_url"`
	SupportedLanguages []string   `json:"supported_languages" gorm:"serializer:json;column:supported_languages"`
	Variables          []agentVar `json:"variables" gorm:"serializer:json"`
	Enable             bool       `json:"-"`
	LlmSvcId           string     `json:"llm_svc_id" gorm:"column:llm_svc_id"`
	TtsSvcId           string     `json:"tts_svc_id" gorm:"column:tts_svc_id"`
}

func (agentConfig) TableName() string { return tableAgent }

type mcpConfig struct {
	Id        string `json:"id" gorm:"column:id"`
	Name      string `json:"name"`
	Transport string `json:"transport"`
	Endpoint  string `json:"endpoint"`
	Enable    bool   `json:"-"`
	ToolCount int    `json:"tool_count" gorm:"column:tool_count"`
}

func (mcpConfig) TableName() string { return tableMcp }

type globalConfig struct {
	Group string `json:"group" gorm:"column:group_name"`
	Key   string `json:"key" gorm:"column:config_key"`
	Value string `json:"value" gorm:"column:config_value"`
	Type  string `json:"type"`
}

func (globalConfig) TableName() string { return tableGlobalConfig }

/* ---------------- 组件 ---------------- */

type modelComp struct {
	cbase.ModuleCompBase
	module *ConfigCenter
}

func (this *modelComp) Init(service core.IService, module core.IModule, comp core.IModuleComp, opt core.IModuleOptions) (err error) {
	this.ModuleCompBase.Init(service, module, comp, opt)
	this.module = module.(*ConfigCenter)
	return
}

// bundle 组装下发给客户端的完整配置（仅启用项）。读表失败容错为空集合。
func (this *modelComp) bundle() map[string]any {
	services := make([]svcConfig, 0)
	if err := postgres.Find(tableSvcConfig, &services, "enable=?", true); err != nil {
		this.module.Warnf("configcenter: 读服务配置失败: %v", err)
	}
	agents := make([]agentConfig, 0)
	if err := postgres.Find(tableAgent, &agents, "enable=?", true); err != nil {
		this.module.Warnf("configcenter: 读 Agent 失败: %v", err)
	}
	mcps := make([]mcpConfig, 0)
	if err := postgres.Find(tableMcp, &mcps, "enable=?", true); err != nil {
		this.module.Warnf("configcenter: 读 MCP 失败: %v", err)
	}
	globals := make([]globalConfig, 0)
	if err := postgres.Find(tableGlobalConfig, &globals, ""); err != nil {
		this.module.Warnf("configcenter: 读全局配置失败: %v", err)
	}
	gm := make(map[string]string, len(globals))
	for _, g := range globals {
		gm[g.Key] = g.Value
	}
	return map[string]any{
		"services": services,
		"agents":   agents,
		"mcps":     mcps,
		"globals":  gm,
	}
}
