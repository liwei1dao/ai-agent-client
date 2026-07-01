package console

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"yunyan/lego/core"
	"yunyan/lego/core/cbase"

	"github.com/golang-jwt/jwt/v4"
)

/* ================= HTTP 组件 ================= */

type httpComp struct {
	cbase.ModuleCompBase
	module  *Console
	options *Options
}

func (this *httpComp) Init(service core.IService, module core.IModule, comp core.IModuleComp, opt core.IModuleOptions) (err error) {
	this.ModuleCompBase.Init(service, module, comp, opt)
	this.module = module.(*Console)
	this.options = opt.(*Options)
	return
}

// Start 启动独立 HTTP 服务（不阻塞主启动流程）。
func (this *httpComp) Start() (err error) {
	mux := http.NewServeMux()
	// API：/console/api/<method>（POST，JSON）。更具体的前缀优先于静态。
	mux.HandleFunc("/console/api/", this.handleAPI)
	// 静态 SPA：/console/* → StaticDir，未命中回落 index.html。
	mux.HandleFunc("/console/", this.serveStatic)
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, "/console/", http.StatusFound)
	})

	addr := this.options.HTTP.Addr
	this.module.Infof("console: HTTP 监听 %s（静态目录 %s）", addr, this.options.StaticDir)
	go func() {
		if e := http.ListenAndServe(addr, mux); e != nil {
			this.module.Errorf("console: HTTP 服务退出: %v", e)
		}
	}()
	return
}

/* ================= 分发 ================= */

type apiResult struct {
	Code int    `json:"code"`
	Msg  string `json:"msg"`
	Data any    `json:"data"`
}

type consoleClaims struct {
	Account  string `json:"account"`
	Identity int    `json:"identity"`
	jwt.RegisteredClaims
}

type handlerFunc func(claims *consoleClaims, body []byte) (any, error)

func (this *httpComp) routes() map[string]handlerFunc {
	return map[string]handlerFunc{
		"login":              this.login,
		"me":                 this.me,
		"getsvcconfigs":      this.getSvcConfigs,
		"addsvcconfig":       this.saveSvcConfig,
		"updatesvcconfig":    this.saveSvcConfig,
		"delsvcconfig":       this.delSvcConfig,
		"getagents":          this.getAgents,
		"addagent":           this.saveAgent,
		"updateagent":        this.saveAgent,
		"delagent":           this.delAgent,
		"getmcpservers":      this.getMcpServers,
		"addmcpserver":       this.saveMcpServer,
		"updatemcpserver":    this.saveMcpServer,
		"delmcpserver":       this.delMcpServer,
		"getglobalconfigs":   this.getGlobalConfigs,
		"addglobalconfig":    this.saveGlobalConfig,
		"updateglobalconfig": this.saveGlobalConfig,
		"delglobalconfig":    this.delGlobalConfig,
	}
}

var publicMethods = map[string]bool{"login": true}

func (this *httpComp) handleAPI(w http.ResponseWriter, r *http.Request) {
	setCORS(w)
	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	method := strings.TrimPrefix(r.URL.Path, "/console/api/")
	h, ok := this.routes()[method]
	if !ok {
		writeJSON(w, &apiResult{Code: 404, Msg: "no such method: " + method})
		return
	}

	var claims *consoleClaims
	if !publicMethods[method] {
		c, err := this.parseToken(r.Header.Get("Authorization"))
		if err != nil {
			writeJSON(w, &apiResult{Code: 401, Msg: "未登录或登录已过期"})
			return
		}
		claims = c
	}

	body, _ := io.ReadAll(r.Body)
	data, err := h(claims, body)
	if err != nil {
		writeJSON(w, &apiResult{Code: 1, Msg: err.Error()})
		return
	}
	writeJSON(w, &apiResult{Code: 0, Msg: "ok", Data: data})
}

/* ================= 鉴权 ================= */

func (this *httpComp) login(_ *consoleClaims, body []byte) (any, error) {
	var req struct {
		Account  string `json:"account"`
		Password string `json:"password"`
	}
	if err := json.Unmarshal(body, &req); err != nil {
		return nil, errors.New("参数错误")
	}
	if req.Account != this.options.AdminAccount || req.Password != this.options.AdminPassword {
		return nil, errors.New("账号或密码错误")
	}
	claims := &consoleClaims{
		Account:  req.Account,
		Identity: 1, // 引导账号固定为超管
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   req.Account,
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(24 * time.Hour)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
		},
	}
	token, err := jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString([]byte(this.options.TokenKey))
	if err != nil {
		return nil, err
	}
	return map[string]any{"token": token, "account": req.Account, "identity": 1}, nil
}

func (this *httpComp) me(claims *consoleClaims, _ []byte) (any, error) {
	return map[string]any{"account": claims.Account, "identity": claims.Identity}, nil
}

func (this *httpComp) parseToken(raw string) (*consoleClaims, error) {
	raw = strings.TrimPrefix(raw, "Bearer ")
	if raw == "" {
		return nil, errors.New("no token")
	}
	claims := &consoleClaims{}
	tok, err := jwt.ParseWithClaims(raw, claims, func(t *jwt.Token) (any, error) {
		return []byte(this.options.TokenKey), nil
	})
	if err != nil || !tok.Valid {
		return nil, errors.New("invalid token")
	}
	return claims, nil
}

/* ================= 服务配置 ================= */

func (this *httpComp) getSvcConfigs(_ *consoleClaims, _ []byte) (any, error) {
	return this.module.model.svcConfigs()
}
func (this *httpComp) saveSvcConfig(_ *consoleClaims, body []byte) (any, error) {
	m := &SvcConfig{}
	if err := json.Unmarshal(body, m); err != nil {
		return nil, err
	}
	if m.Id == "" {
		return nil, errors.New("服务 ID 不能为空")
	}
	return nil, this.module.model.saveSvcConfig(m)
}
func (this *httpComp) delSvcConfig(_ *consoleClaims, body []byte) (any, error) {
	return nil, this.module.model.delSvcConfig(idOf(body))
}

/* ================= Agent ================= */

func (this *httpComp) getAgents(_ *consoleClaims, _ []byte) (any, error) {
	return this.module.model.agents()
}
func (this *httpComp) saveAgent(_ *consoleClaims, body []byte) (any, error) {
	m := &Agent{}
	if err := json.Unmarshal(body, m); err != nil {
		return nil, err
	}
	if m.AgentId == "" {
		return nil, errors.New("Agent ID 不能为空")
	}
	return nil, this.module.model.saveAgent(m)
}
func (this *httpComp) delAgent(_ *consoleClaims, body []byte) (any, error) {
	var req struct {
		AgentId string `json:"agent_id"`
	}
	json.Unmarshal(body, &req)
	return nil, this.module.model.delAgent(req.AgentId)
}

/* ================= MCP ================= */

func (this *httpComp) getMcpServers(_ *consoleClaims, _ []byte) (any, error) {
	return this.module.model.mcpServers()
}
func (this *httpComp) saveMcpServer(_ *consoleClaims, body []byte) (any, error) {
	m := &McpServer{}
	if err := json.Unmarshal(body, m); err != nil {
		return nil, err
	}
	if m.Id == "" {
		return nil, errors.New("MCP ID 不能为空")
	}
	return nil, this.module.model.saveMcpServer(m)
}
func (this *httpComp) delMcpServer(_ *consoleClaims, body []byte) (any, error) {
	return nil, this.module.model.delMcpServer(idOf(body))
}

/* ================= 全局配置 ================= */

func (this *httpComp) getGlobalConfigs(_ *consoleClaims, _ []byte) (any, error) {
	return this.module.model.globalConfigs()
}
func (this *httpComp) saveGlobalConfig(_ *consoleClaims, body []byte) (any, error) {
	m := &GlobalConfigItem{}
	if err := json.Unmarshal(body, m); err != nil {
		return nil, err
	}
	if m.Key == "" {
		return nil, errors.New("key 不能为空")
	}
	return nil, this.module.model.saveGlobalConfig(m)
}
func (this *httpComp) delGlobalConfig(_ *consoleClaims, body []byte) (any, error) {
	var req struct {
		Id uint64 `json:"id"`
	}
	json.Unmarshal(body, &req)
	return nil, this.module.model.delGlobalConfig(req.Id)
}

/* ================= 静态 / 工具 ================= */

// serveStatic 托管 StaticDir，未命中文件回落 index.html（SPA 路由）。
func (this *httpComp) serveStatic(w http.ResponseWriter, r *http.Request) {
	dir := this.options.StaticDir
	rel := strings.TrimPrefix(r.URL.Path, "/console/")
	if rel == "" {
		rel = "index.html"
	}
	full := filepath.Join(dir, filepath.Clean("/"+rel))
	if fi, err := os.Stat(full); err == nil && !fi.IsDir() {
		http.ServeFile(w, r, full)
		return
	}
	http.ServeFile(w, r, filepath.Join(dir, "index.html"))
}

func idOf(body []byte) string {
	var req struct {
		Id string `json:"id"`
	}
	json.Unmarshal(body, &req)
	return req.Id
}

func setCORS(w http.ResponseWriter) {
	h := w.Header()
	h.Set("Access-Control-Allow-Origin", "*")
	h.Set("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
	h.Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
}

func writeJSON(w http.ResponseWriter, v *apiResult) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	json.NewEncoder(w).Encode(v)
}
