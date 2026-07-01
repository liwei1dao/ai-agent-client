package app

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"yunyan/lego/core"
	"yunyan/lego/core/cbase"
	wechat "yunyan/sys/auth/wechat"
	"yunyan/sys/email"
	"yunyan/sys/sms"

	"github.com/golang-jwt/jwt/v4"
)

/* ================= HTTP 组件 ================= */

type httpComp struct {
	cbase.ModuleCompBase
	module  *App
	options *Options
}

func (this *httpComp) Init(service core.IService, module core.IModule, comp core.IModuleComp, opt core.IModuleOptions) (err error) {
	this.ModuleCompBase.Init(service, module, comp, opt)
	this.module = module.(*App)
	this.options = opt.(*Options)
	return
}

func (this *httpComp) Start() (err error) {
	mux := http.NewServeMux()
	mux.HandleFunc("/app/api/", this.handleAPI)
	addr := this.options.HTTP.Addr
	this.module.Infof("app: HTTP 监听 %s", addr)
	go func() {
		if e := http.ListenAndServe(addr, mux); e != nil {
			this.module.Errorf("app: HTTP 服务退出: %v", e)
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

type appClaims struct {
	Uid     uint64 `json:"uid"`
	Channel string `json:"channel"`
	jwt.RegisteredClaims
}

type handlerFunc func(claims *appClaims, body []byte) (any, error)

func (this *httpComp) routes() map[string]handlerFunc {
	return map[string]handlerFunc{
		"sendcode":  this.sendCode,
		"login":     this.login,
		"getconfig": this.getConfig,
		"me":        this.me,
	}
}

var publicMethods = map[string]bool{"sendcode": true, "login": true}

func (this *httpComp) handleAPI(w http.ResponseWriter, r *http.Request) {
	setCORS(w)
	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	method := strings.TrimPrefix(r.URL.Path, "/app/api/")
	h, ok := this.routes()[method]
	if !ok {
		writeJSON(w, &apiResult{Code: 404, Msg: "no such method: " + method})
		return
	}
	var claims *appClaims
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

/* ================= 发送验证码 ================= */

func (this *httpComp) sendCode(_ *appClaims, body []byte) (any, error) {
	var req struct {
		Channel string `json:"channel"` // email / sms
		Target  string `json:"target"`
	}
	if err := json.Unmarshal(body, &req); err != nil || req.Target == "" {
		return nil, errors.New("参数错误")
	}
	code := genCode()
	if err := this.module.model.saveCode(req.Channel, req.Target, code, this.options.CodeTTL); err != nil {
		return nil, fmt.Errorf("验证码下发失败: %w", err)
	}
	// 开发期日志可见（生产请移除）
	this.module.Infof("app: 验证码 %s -> %s/%s", code, req.Channel, req.Target)

	switch req.Channel {
	case "email":
		if err := email.SendMail("验证码", fmt.Sprintf("您的验证码是 %s，%d 分钟内有效。", code, this.options.CodeTTL/60), req.Target); err != nil {
			return nil, fmt.Errorf("邮件发送失败: %w", err)
		}
	case "sms":
		if err := sms.SendCaptcha(req.Target, code); err != nil {
			return nil, fmt.Errorf("短信发送失败: %w", err)
		}
	default:
		return nil, errors.New("不支持的验证码渠道")
	}
	return map[string]any{"sent": true}, nil
}

/* ================= 登录（邮箱/短信/微信） ================= */

func (this *httpComp) login(_ *appClaims, body []byte) (any, error) {
	var req struct {
		Channel string `json:"channel"` // email / sms / wechat
		Target  string `json:"target"`  // 邮箱 / 手机号
		Code    string `json:"code"`    // 邮箱/短信验证码
		WxCode  string `json:"wxcode"`  // 微信授权 code
	}
	if err := json.Unmarshal(body, &req); err != nil {
		return nil, errors.New("参数错误")
	}

	var u *User
	switch req.Channel {
	case "email":
		if !this.module.model.checkCode("email", req.Target, req.Code) {
			return nil, errors.New("验证码错误或已过期")
		}
		if x, ok := this.module.model.userByField("email", req.Target); ok {
			u = x
		} else {
			u = &User{Email: req.Target, Channel: "email"}
		}
	case "sms":
		if !this.module.model.checkCode("sms", req.Target, req.Code) {
			return nil, errors.New("验证码错误或已过期")
		}
		if x, ok := this.module.model.userByField("phone", req.Target); ok {
			u = x
		} else {
			u = &User{Phone: req.Target, Channel: "sms"}
		}
	case "wechat":
		info, err := wechat.Auth(context.Background(), req.WxCode)
		if err != nil {
			return nil, fmt.Errorf("微信授权失败: %w", err)
		}
		if x, ok := this.module.model.userByField("openid", info.OpenID); ok {
			u = x
		} else {
			u = &User{Openid: info.OpenID, Channel: "wechat"}
		}
		u.Unionid = info.UnionID
		u.Nickname = info.Nickname
		u.Avatar = info.HeadImgURL
	default:
		return nil, errors.New("不支持的登录方式")
	}

	if err := this.module.model.saveUser(u); err != nil {
		return nil, fmt.Errorf("用户落库失败: %w", err)
	}
	token, err := this.issueToken(u)
	if err != nil {
		return nil, err
	}
	return map[string]any{"token": token, "user": u}, nil
}

/* ================= 获取应用配置 / me ================= */

func (this *httpComp) getConfig(_ *appClaims, _ []byte) (any, error) {
	return this.module.model.configBundle(), nil
}

func (this *httpComp) me(claims *appClaims, _ []byte) (any, error) {
	u := &User{}
	if x, ok := this.module.model.userByField("uid", fmt.Sprintf("%d", claims.Uid)); ok {
		u = x
	}
	return u, nil
}

/* ================= JWT ================= */

func (this *httpComp) issueToken(u *User) (string, error) {
	claims := &appClaims{
		Uid:     u.Uid,
		Channel: u.Channel,
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   fmt.Sprintf("%d", u.Uid),
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(30 * 24 * time.Hour)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
		},
	}
	return jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString([]byte(this.options.TokenKey))
}

func (this *httpComp) parseToken(raw string) (*appClaims, error) {
	raw = strings.TrimPrefix(raw, "Bearer ")
	if raw == "" {
		return nil, errors.New("no token")
	}
	claims := &appClaims{}
	tok, err := jwt.ParseWithClaims(raw, claims, func(t *jwt.Token) (any, error) {
		return []byte(this.options.TokenKey), nil
	})
	if err != nil || !tok.Valid {
		return nil, errors.New("invalid token")
	}
	return claims, nil
}

/* ================= 工具 ================= */

func genCode() string {
	b := make([]byte, 3)
	rand.Read(b)
	n := (int(b[0])<<16 | int(b[1])<<8 | int(b[2])) % 1000000
	return fmt.Sprintf("%06d", n)
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
