package services

import (
	"yunyan/comm"
	"reflect"

	"google.golang.org/protobuf/proto"
)

var (
	typeOfMessage                = reflect.TypeOf((*proto.Message)(nil)).Elem()
	typeOfByteSlice              = reflect.TypeOf([]byte{}) // []byte 类型
	httpResultTyoe  reflect.Type = reflect.TypeOf(&comm.HttpResult{})
)

// 用户协议处理函数注册的反射对象
type msghandle struct {
	rcvr    reflect.Value
	msgType reflect.Type   //消息请求类型
	handle  reflect.Method //处理函数
	encrypt bool           //是否加密
}
