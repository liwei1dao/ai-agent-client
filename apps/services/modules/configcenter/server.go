package configcenter

import (
	"encoding/json"
	"net/http"

	"yunyan/lego/core"
	"yunyan/lego/core/cbase"
)

type httpComp struct {
	cbase.ModuleCompBase
	module  *ConfigCenter
	options *Options
}

func (this *httpComp) Init(service core.IService, module core.IModule, comp core.IModuleComp, opt core.IModuleOptions) (err error) {
	this.ModuleCompBase.Init(service, module, comp, opt)
	this.module = module.(*ConfigCenter)
	this.options = opt.(*Options)
	return
}

func (this *httpComp) Start() (err error) {
	mux := http.NewServeMux()
	// 公开、免登录：获取整包加密的应用配置。
	mux.HandleFunc("/config/api/getappconfig", this.getAppConfig)
	mux.HandleFunc("/config/api/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ok"))
	})

	if _, fromEnv := deriveKey(this.options.SecretEnv); !fromEnv {
		this.module.Warnf("configcenter: 环境变量 %s 未设置，正在使用开发回退密钥（生产务必配置！）", this.options.SecretEnv)
	}
	addr := this.options.HTTP.Addr
	this.module.Infof("configcenter: HTTP 监听 %s（公开配置接口 /config/api/getappconfig）", addr)
	go func() {
		if e := http.ListenAndServe(addr, mux); e != nil {
			this.module.Errorf("configcenter: HTTP 服务退出: %v", e)
		}
	}()
	return
}

type apiResult struct {
	Code int    `json:"code"`
	Msg  string `json:"msg"`
	Data any    `json:"data"`
}

// getAppConfig 公开接口：组装配置 → 整包 AES-256-GCM 加密 → 返回 { code, data:{ enc } }。
func (this *httpComp) getAppConfig(w http.ResponseWriter, r *http.Request) {
	setCORS(w)
	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	bundle := this.module.model.bundle()
	plaintext, err := json.Marshal(bundle)
	if err != nil {
		writeJSON(w, &apiResult{Code: 1, Msg: "配置序列化失败"})
		return
	}
	enc, err := encryptJSON(this.options.SecretEnv, plaintext)
	if err != nil {
		writeJSON(w, &apiResult{Code: 1, Msg: "配置加密失败: " + err.Error()})
		return
	}
	writeJSON(w, &apiResult{Code: 0, Msg: "ok", Data: map[string]any{"enc": enc}})
}

func setCORS(w http.ResponseWriter) {
	h := w.Header()
	h.Set("Access-Control-Allow-Origin", "*")
	h.Set("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
	h.Set("Access-Control-Allow-Headers", "Content-Type")
}

func writeJSON(w http.ResponseWriter, v *apiResult) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	json.NewEncoder(w).Encode(v)
}
