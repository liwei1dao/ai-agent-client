package modules

import (
	"yunyan/comm"
	"yunyan/pb"
	"reflect"

	"google.golang.org/protobuf/proto"
)

var (
	typeOfSession   = reflect.TypeOf((*comm.IUserSession)(nil)).Elem()
	typeOfMessage   = reflect.TypeOf((*proto.Message)(nil)).Elem()
	typeOfByteSlice = reflect.TypeOf([]byte{}) // []byte 类型
	typeOfErrorCode = reflect.TypeOf((*pb.ErrorCode)(nil)).Elem()
	typeOfErrorData = reflect.TypeOf((*pb.ErrorData)(nil))
	typeOfError     = reflect.TypeOf((*error)(nil)).Elem()
)
