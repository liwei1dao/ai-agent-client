package modules

import (
	"context"
	"yunyan/comm"
	"fmt"
	"log"
	"reflect"
	"strings"
	"unicode"
	"unicode/utf8"

	"yunyan/lego/base"
	"yunyan/lego/core"
	"yunyan/lego/core/cbase"
)

/*
模块网关组件的基类实现 模块接收用户的消息请求都需要通过装备继承此组件的api组件来实现
*/

// var typeOfContext = reflect.TypeOf((*context.Context)(nil)).Elem()
var typeOfContext = reflect.TypeOf((*context.Context)(nil)).Elem()

/*
模块 网关组件 接收处理用户传递消息
*/
type MCompHttpGate struct {
	cbase.ModuleCompBase
	service     base.IRPCXService //rpc服务对象
	module      core.IModule      //当前业务模块
	comp        core.IModuleComp  //网关组件自己
	scomp       comm.ISC_HttpRouteComp
	Version     string   //版本标识
	EncryptMsgs []string //加密协议
}

// 组件初始化接口
func (this *MCompHttpGate) Init(service core.IService, module core.IModule, comp core.IModuleComp, options core.IModuleOptions) (err error) {
	this.ModuleCompBase.Init(service, module, comp, options)
	this.service = service.(base.IRPCXService)
	this.module = module
	this.comp = comp
	return
}

// 组件启动接口，启动时将自己接收用户消息的处理函数注册到services/comp_gateroute.go 对象中
func (this *MCompHttpGate) Start() (err error) {
	if err = this.ModuleCompBase.Start(); err != nil {
		return
	}
	var comp core.IServiceComp
	//注册远程路由
	if comp, err = this.service.GetComp(comm.SC_ServiceHttpRouteComp); err != nil {
		return
	}
	this.scomp = comp.(comm.ISC_HttpRouteComp)
	this.suitableMethods()
	return
}

// 反射注册相关接口道services/comp_gateroute.go 对象中
func (this *MCompHttpGate) suitableMethods() {
	typ := reflect.TypeOf(this.comp)
	for m := 0; m < typ.NumMethod(); m++ {
		method := typ.Method(m)
		mname := method.Name
		if mname == "Start" ||
			mname == "Init" ||
			mname == "Destroy" ||
			strings.HasSuffix(mname, "Check") {
			continue
		}
		this.reflectionRouteHandle(typ, method)
	}
}

// 反射注册路由处理函数
func (this *MCompHttpGate) reflectionRouteHandle(typ reflect.Type, method reflect.Method) (ret bool) {
	mtype := method.Type
	mname := method.Name
	isEncrypt := false
	if method.PkgPath != "" {
		log.Panicf("反射注册用户处理函数错误 [%s-%s] Api接口格式错误", this.module.GetType(), mname)
		return
	}
	if mtype.NumIn() != 3 {
		log.Panicf("反射注册用户处理函数错误 [%s-%s] Api接口格式错误", this.module.GetType(), mname)
		return
	}
	contextType := mtype.In(1)
	if !contextType.Implements(typeOfSession) {
		log.Panicf("反射注册用户处理函数错误 [%s-%s] Api接口格式错误", this.module.GetType(), mname)
		return
	}
	agrType := mtype.In(2)
	if !agrType.Implements(typeOfMessage) {
		log.Panicf("反射注册用户处理函数错误 [%s-%s] Api接口格式错误", this.module.GetType(), mname)
		return
	}
	if mtype.NumOut() != 2 {
		log.Panicf("反射注册用户处理函数错误 [%s-%s] Api接口格式错误", this.module.GetType(), mname)
		return
	}
	returnDataType := mtype.Out(0)
	if !returnDataType.Implements(typeOfMessage) && returnDataType != typeOfByteSlice {
		log.Panicf("反射注册用户处理函数错误 [%s-%s] Api接口格式错误", this.module.GetType(), mname)
		return
	}

	returnErrDataType := mtype.Out(1)
	if returnErrDataType != typeOfErrorData {
		log.Panicf("反射注册用户处理函数错误 [%s-%s] Api接口格式错误", this.module.GetType(), mname)
		return
	}

	if this.EncryptMsgs != nil && len(this.EncryptMsgs) > 0 {
		for _, v := range this.EncryptMsgs {
			if v == mname {
				isEncrypt = true
				break
			}
		}
	}

	//注册路由函数
	if this.Version == "" {
		this.scomp.RegisterRoute(fmt.Sprintf("%s_%s", this.module.GetType(), strings.ToLower(mname)), isEncrypt, reflect.ValueOf(this.comp), agrType, method)
	} else {
		this.scomp.RegisterRoute(fmt.Sprintf("%s_%s_%s", this.module.GetType(), strings.ToLower(mname), this.Version), isEncrypt, reflect.ValueOf(this.comp), agrType, method)
	}
	return true
}

func (this *MCompHttpGate) isExportedOrBuiltinType(t reflect.Type) bool {
	for t.Kind() == reflect.Ptr {
		t = t.Elem()
	}
	return this.isExported(t.Name()) || t.PkgPath() == ""
}

func (this *MCompHttpGate) isExported(name string) bool {
	rune, _ := utf8.DecodeRuneInString(name)
	return unicode.IsUpper(rune)
}
