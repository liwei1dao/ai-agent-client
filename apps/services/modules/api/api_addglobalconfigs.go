package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// 添加全局第三方服务配置
func (this *apiComp) AddGlobalConfigs(session comm.IUserSession, req *pb.ApiAddGlobalConfigsReq) (resp *pb.ApiAddGlobalConfigsResp, errdata *pb.ErrorData) {
	var (
		err error
	)
	if err = this.module.model.addglobalconfig(req.Configs...); err != nil {
		errdata = &pb.ErrorData{
			Code: pb.ErrorCode_DBError,

			Message: err.Error(),
		}
		this.module.Error("AddGlobalConfig Fail!", log.Field{Key: "uid", Value: session.GetUserId()}, log.Field{Key: "err", Value: err.Error()})
		return
	}
	if err = this.service.RpcBroadcast(session, comm.Service_Home, string(comm.Rpc_ModifyAppConifg), &pb.Rpc_EmptyReq{}, nil); err != nil {
		this.module.Error("广播失败了!", log.Field{Key: "err", Value: err.Error()})
	}
	resp = &pb.ApiAddGlobalConfigsResp{}
	return
}
