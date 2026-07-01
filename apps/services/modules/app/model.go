package app

import (
	"context"
	"time"

	"yunyan/lego/core"
	"yunyan/lego/core/cbase"
	"yunyan/lego/sys/postgres"
	legoredis "yunyan/lego/sys/redis"
)

const (
	tableUser = "app_user"
	// console 写入的配置表（app 只读下发给客户端）
	tableConsoleGlobal = "console_global_config"
	tableConsoleAgent  = "console_agent"
)

/* ---------------- 模型 ---------------- */

// User 客户端用户（邮箱/手机/微信任一登录即建档）。
type User struct {
	Uid        uint64 `json:"uid" gorm:"primaryKey;autoIncrement"`
	Email      string `json:"email" gorm:"index"`
	Phone      string `json:"phone" gorm:"index"`
	Openid     string `json:"openid" gorm:"index"`
	Unionid    string `json:"unionid"`
	Nickname   string `json:"nickname"`
	Avatar     string `json:"avatar"`
	Channel    string `json:"channel"` // email / sms / wechat
	Createtime int64  `json:"createtime"`
	Updatetime int64  `json:"updatetime"`
}

func (User) TableName() string { return tableUser }

// cfgGlobal 读 console_global_config 的精简视图。
type cfgGlobal struct {
	Group string `json:"group" gorm:"column:group_name"`
	Key   string `json:"key" gorm:"column:config_key"`
	Value string `json:"value" gorm:"column:config_value"`
	Type  string `json:"type"`
}

func (cfgGlobal) TableName() string { return tableConsoleGlobal }

// cfgAgent 读 console_agent 的精简视图（仅启用项下发）。
type cfgAgent struct {
	AgentId     string `json:"agent_id" gorm:"column:agent_id"`
	Name        string `json:"name"`
	Type        string `json:"type"`
	AvatarUrl   string `json:"avatar_url" gorm:"column:avatar_url"`
	Description string `json:"description"`
	Enable      bool   `json:"enable"`
}

func (cfgAgent) TableName() string { return tableConsoleAgent }

/* ---------------- 组件 ---------------- */

type modelComp struct {
	cbase.ModuleCompBase
	module *App
}

func (this *modelComp) Init(service core.IService, module core.IModule, comp core.IModuleComp, opt core.IModuleOptions) (err error) {
	this.ModuleCompBase.Init(service, module, comp, opt)
	this.module = module.(*App)
	if e := postgres.CreateTable(tableUser, &User{}); e != nil {
		this.module.Errorln(e)
	}
	return
}

/* ---- 验证码（Redis） ---- */

func vcodeKey(channel, target string) string {
	return legoredis.RKey("vcode:" + channel + ":" + target)
}

func (this *modelComp) saveCode(channel, target, code string, ttl int) error {
	return legoredis.Conn().Set(context.Background(), vcodeKey(channel, target), code, time.Duration(ttl)*time.Second).Err()
}

func (this *modelComp) checkCode(channel, target, code string) bool {
	got, err := legoredis.Conn().Get(context.Background(), vcodeKey(channel, target)).Result()
	if err != nil || got == "" || got != code {
		return false
	}
	legoredis.Conn().Del(context.Background(), vcodeKey(channel, target))
	return true
}

/* ---- 用户 ---- */

func (this *modelComp) userByField(col, val string) (*User, bool) {
	u := &User{}
	if err := postgres.FindOne(tableUser, u, col+"=?", val); err != nil || u.Uid == 0 {
		return nil, false
	}
	return u, true
}

func (this *modelComp) saveUser(u *User) error {
	now := time.Now().Unix()
	if u.Createtime == 0 {
		u.Createtime = now
	}
	u.Updatetime = now
	return postgres.Save(tableUser, u)
}

/* ---- 应用配置（读 console 表，容错） ---- */

func (this *modelComp) configBundle() map[string]any {
	globals := make([]cfgGlobal, 0)
	if err := postgres.Find(tableConsoleGlobal, &globals, ""); err != nil {
		this.module.Warnf("读取全局配置失败（console 表可能尚未建）: %v", err)
	}
	agents := make([]cfgAgent, 0)
	if err := postgres.Find(tableConsoleAgent, &agents, "enable=?", true); err != nil {
		this.module.Warnf("读取 Agent 配置失败: %v", err)
	}
	gm := make(map[string]string, len(globals))
	for _, g := range globals {
		gm[g.Key] = g.Value
	}
	return map[string]any{"globals": gm, "agents": agents}
}
