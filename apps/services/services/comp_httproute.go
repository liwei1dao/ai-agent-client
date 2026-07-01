package services

import (
	"context"
	"yunyan/comm"
	"yunyan/pb"
	"fmt"
	"reflect"
	"time"

	jsoniter "github.com/json-iterator/go"

	"yunyan/lego/core"
	"yunyan/lego/core/cbase"
	"yunyan/lego/sys/log"
	"yunyan/lego/sys/pools"
)

// 加密信号：业务服务仅上报“该接口需要加密”，具体加密动作由网关模块执行。
// 信号通过 Rpc_GatewayHttpRouteResp.Encrypted 字段传递。

var json = jsoniter.Config{
	EscapeHTML:                    true,
	SortMapKeys:                   true,
	ValidateJsonRawMessage:        true,
	ObjectFieldMustBeSimpleString: false,
	CaseSensitive:                 false,
	UseNumber:                     true, // 允许字符串转数字的预处理
	DisallowUnknownFields:         false,
}.Froze()

/*
	服务网关组件 用于接收网关服务发送过来的消息
*/

// NewHttpRouteComp 创建路由组件。业务服务不会在这里做加密，只会根据业务声明的 EncryptMsgs
// 在响应中携带“需要加密”信号，由网关模块统一加密。
func NewHttpRouteComp() comm.ISC_HttpRouteComp {
	comp := new(SCompHttpRoute)
	return comp
}

// 服务网关组件
type SCompHttpRoute struct {
	cbase.ServiceCompBase

	service      comm.IService         //rpc服务对象 通过这个对象可以发布服务和调用其他服务的接口
	msghandles   map[string]*msghandle //处理函数的管理对象
	interceptors []comm.ApiInterceptor //API 请求拦截器链，由业务模块注册
	auditHook    []comm.ApiAuditFunc   //API 审计回调钩子，由业务模块注册
}

// AddInterceptor 添加 API 请求拦截器（在 handler 执行前调用）
func (this *SCompHttpRoute) AddInterceptor(interceptor comm.ApiInterceptor) {
	this.interceptors = append(this.interceptors, interceptor)
}

// AddApiAuditHook 添加 API 审计回调钩子
func (this *SCompHttpRoute) AddApiAuditHook(hook comm.ApiAuditFunc) {
	this.auditHook = append(this.auditHook, hook)
}

// 设置服务组件名称 方便业务模块中获取此组件对象
func (this *SCompHttpRoute) GetName() core.S_Comps {
	return comm.SC_ServiceHttpRouteComp
}

// 组件初始化函数
func (this *SCompHttpRoute) Init(service core.IService, comp core.IServiceComp, options core.ICompOptions) (err error) {
	err = this.ServiceCompBase.Init(service, comp, options)
	this.service = service.(comm.IService)
	this.msghandles = make(map[string]*msghandle)
	pools.InitTypes(httpResultTyoe)
	return err
}

// 组件启动时注册rpc服务监听
func (this *SCompHttpRoute) Start() (err error) {
	this.service.Register(string(comm.Rpc_GatewayHttpRoute), this.Rpc_GatewayHttpRoute) //注册网关路由接收接口
	err = this.ServiceCompBase.Start()
	return
}

// 业务模块注册用户消息处理路由
func (this *SCompHttpRoute) RegisterRoute(methodName string, isEncrypt bool, comp reflect.Value, msg reflect.Type, handele reflect.Method) {
	log.Debugf("注册用户路由【%s】", methodName)
	_, ok := this.msghandles[methodName]
	if ok {
		log.Errorf("重复 注册网关消息【%s】", methodName)
		return
	}
	this.msghandles[methodName] = &msghandle{
		rcvr:    comp,
		msgType: msg,
		handle:  handele,
		encrypt: isEncrypt,
	}
	//注册类型池
	pools.InitTypes(msg)
}

// Rpc_GatewayRoute服务接口的接收函数
func (this *SCompHttpRoute) Rpc_GatewayHttpRoute(ctx context.Context, args *pb.Rpc_GatewayHttpRouteReq, reply *pb.Rpc_GatewayHttpRouteResp) (err error) {
	var (
		msghandle  *msghandle
		session    comm.IUserSession
		msg        interface{}
		httpResult *comm.HttpResult = pools.GetForType(httpResultTyoe).(*comm.HttpResult)
		errordata  *pb.ErrorData
		ok         bool
	)
	defer func() {
		pools.PutForType(httpResultTyoe, httpResult)
		if session != nil {
			this.service.PutUserSession(session)
		}
	}()
	msghandle, ok = this.msghandles[args.MsgName]
	if ok {
		session = this.service.GetUserSession(ctx, args.Meta)
		stime := time.Now()
		var auditCode int32 = 0

		//序列化用户消息对象
		msg = pools.GetForType(msghandle.msgType)
		if len(args.Message) > 0 {
			if err = json.Unmarshal(args.Message, msg); err != nil {
				log.Errorf("[Handle Api] UserMessage:%s Unmarshal err:%v", args.MsgName, err)
				return err
			}
		}

		// 执行拦截器链
		for _, interceptor := range this.interceptors {
			if errData := interceptor(args.MsgName, session, msg); errData != nil {
				httpResult.Code = errData.Code
				httpResult.Message = errData.Message
				httpResult.Data = nil
				reply.ContentType = "application/json"
				reply.Body, err = json.Marshal(httpResult)
				return nil
			}
		}

		//执行处理流
		handlereturn := msghandle.handle.Func.Call([]reflect.Value{msghandle.rcvr, reflect.ValueOf(session), reflect.ValueOf(msg)})
		errdata := handlereturn[1]
		if !errdata.IsNil() { //处理返货错误码 返回用户错误信息
			errordata = errdata.Interface().(*pb.ErrorData)
			httpResult.Code = errordata.Code
			httpResult.Message = errordata.Message
			httpResult.Data = nil
			reply.ContentType = "application/json"
			reply.Body, err = json.Marshal(httpResult)
			auditCode = int32(errordata.Code)
			log.Error("[Handle Api]",
				log.Field{Key: "t", Value: time.Since(stime).Milliseconds()},
				log.Field{Key: "m", Value: args.MsgName},
				log.Field{Key: "meta", Value: args.Meta},
				log.Field{Key: "req", Value: msg},
				log.Field{Key: "reply", Value: httpResult},
			)
		} else {
			returnVal := handlereturn[0]
			returnType := returnVal.Type()

			if returnType.Implements(typeOfMessage) {
				httpResult.Code = pb.ErrorCode_Success
				httpResult.Message = "Success"
				httpResult.Data = handlereturn[0].Interface()
				log.Debug("[Handle Api]",
					log.Field{Key: "t", Value: time.Since(stime).Milliseconds()},
					log.Field{Key: "m", Value: args.MsgName},
					log.Field{Key: "meta", Value: args.Meta},
					log.Field{Key: "req", Value: msg},
					// log.Field{Key: "reply", Value: httpResult},
				)
				reply.ContentType = "application/json"
				reply.Body, err = json.Marshal(httpResult)
			} else if returnType == typeOfByteSlice {
				log.Debug("[Handle Api]",
					log.Field{Key: "t", Value: time.Since(stime).Milliseconds()},
					log.Field{Key: "m", Value: args.MsgName},
					log.Field{Key: "meta", Value: args.Meta},
					log.Field{Key: "req", Value: msg},
					// log.Field{Key: "reply_bytes", Value: len(returnVal.Bytes())},
				)
				if ct := session.GetMateToString("content_type"); ct != "" {
					reply.ContentType = ct
				} else {
					reply.ContentType = "application/json"
				}
				reply.Body = returnVal.Bytes()
			}
		}

		// 异步通知审计钩子（避免阻塞主请求流程）—— 在加密信号附加之前 clone reply.Body，仅记录明文供审计使用
		if len(this.auditHook) > 0 {
			auditSession := session.Clone()
			reqBody := make([]byte, len(args.Message))
			copy(reqBody, args.Message)
			respBody := make([]byte, len(reply.Body))
			copy(respBody, reply.Body)
			costMs := time.Since(stime).Milliseconds()
			msgName := args.MsgName
			hooks := this.auditHook
			go func() {
				defer func() {
					if r := recover(); r != nil {
						log.Errorf("[AuditHook] panic: %v, api: %s", r, msgName)
					}
				}()
				for _, v := range hooks {
					v(msgName, auditSession, reqBody, respBody, auditCode, costMs)
				}
			}()
		}

		// ===== 加密信号上报 =====
		// 业务服务不执行加密动作，只在 reply 中标记 Encrypted=true，由网关模块根据配置的 key 统一加密。
		// 仅对 application/json 响应标记加密，裸 bytes 文件流不参与加密。
		if msghandle.encrypt && len(reply.Body) > 0 && reply.ContentType == "application/json" {
			reply.Encrypted = true
		}
	} else { //未找到消息处理函数
		log.Errorf("[Handle Api] no found handle %s", args.MsgName)
		httpResult.Code = pb.ErrorCode_NoFindServiceHandleFunc
		httpResult.Message = fmt.Sprintf("[Handle Http] no found handle %s", args.MsgName)
		httpResult.Data = nil
		reply.ContentType = "application/json"
		reply.Body, err = json.Marshal(httpResult)
	}

	return nil
}
