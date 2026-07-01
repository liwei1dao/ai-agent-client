package comm

import (
	"context"
	"yunyan/lego/utils"
	"fmt"
	"sync"
)

// session Session 临时数据key
const (
	SessionMeta_SessionId  = "sessionid"  //会话Id
	SessionMeta_IP         = "ip"         //IP地址
	SessionMeta_UserId     = "userid"     //用户id
	SessionMeta_ServiceTag = "servicetag" //集群标签
)

func NewUserSession() IUserSession {
	return &UserSession{
		meta:  make(map[string]string),
		cache: make(map[string]interface{}),
	}
}

// 用户会话
type UserSession struct {
	context.Context
	metalock  sync.RWMutex
	meta      map[string]string
	cachelock sync.RWMutex
	cache     map[string]interface{}
}

// 重置
func (this *UserSession) SetSession(ctx context.Context, meta map[string]string) {
	this.Context = ctx
	for k, v := range meta {
		this.meta[k] = v
	}
}

// 重置
func (this *UserSession) Reset() {
	this.meta = make(map[string]string)
	this.cache = make(map[string]interface{})
}

func (this *UserSession) GetMateToString(key string) string {
	value, _ := this.GetMate(key)
	return value
}
func (this *UserSession) GetMateToInt64(key string) int64 {
	value, _ := this.GetMate(key)
	return utils.StringToInt64(value)
}
func (this *UserSession) GetMateToUInt64(key string) uint64 {
	value, _ := this.GetMate(key)
	return utils.StringToUInt64(value)
}
func (this *UserSession) GetMateToInt32(key string) int32 {
	value, _ := this.GetMate(key)
	return int32(utils.StringToInt64(value))
}

func (this *UserSession) GetMateToFloat64(key string) float64 {
	value, _ := this.GetMate(key)
	return utils.StringToFloat64(value)
}
func (this *UserSession) SetMateForFloat64(key string, value float64) {
	this.SetMate(key, fmt.Sprintf("%f", value))
}

func (this *UserSession) SetMateForInt64(key string, value int64) {
	this.SetMate(key, fmt.Sprintf("%d", value))
}
func (this *UserSession) GetMateToBool(key string) bool {
	value, _ := this.GetMate(key)
	return utils.StringToInt64(value) == 1
}

// 获取IP
func (this *UserSession) GetIP() string {
	value, _ := this.GetMate(SessionMeta_IP)
	return value
}

// 获取用户id
func (this *UserSession) GetServiceTag() string {
	value, _ := this.GetMate(SessionMeta_ServiceTag)
	return value
}

// 获取用户id
func (this *UserSession) GetSessionId() string {
	value, _ := this.GetMate(SessionMeta_SessionId)
	return value
}
func (this *UserSession) GetUserId() string {
	value, _ := this.GetMate(SessionMeta_UserId)
	return value
}

// 写入元数据
func (this *UserSession) SetMate(name, value string) {
	this.metalock.Lock()
	this.meta[name] = value
	this.metalock.Unlock()
}

func (this *UserSession) SetMates(meta map[string]string) {
	this.metalock.Lock()
	for k, v := range meta {
		this.meta[k] = v
	}
	this.metalock.Unlock()
}

// 写入元数据
func (this *UserSession) GetMate(name string) (value string, ok bool) {
	this.metalock.RLock()
	value, ok = this.meta[name]
	this.metalock.RUnlock()
	return
}

// 写入元数据
func (this *UserSession) SetCache(name string, value interface{}) {
	this.cachelock.Lock()
	this.cache[name] = value
	this.cachelock.Unlock()
}

// 写入元数据
func (this *UserSession) GetCache(name string) (value interface{}, ok bool) {
	this.cachelock.RLock()
	value, ok = this.cache[name]
	this.cachelock.RUnlock()
	return
}

// 克隆
func (this *UserSession) Clone() (session IUserSession) {
	session = NewUserSession()
	this.metalock.RLock()
	for k, v := range this.meta {
		session.SetMate(k, v)
	}
	this.metalock.RUnlock()
	this.cachelock.RLock()
	for k, v := range this.cache {
		session.SetCache(k, v)
	}
	this.cachelock.RUnlock()
	return
}

func (this *UserSession) GetMetas() (meta map[string]string) {
	meta = make(map[string]string)
	this.metalock.RLock()
	for k, v := range this.meta {
		meta[k] = v
	}
	this.metalock.RUnlock()
	return
}
