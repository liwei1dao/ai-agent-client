package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// 更新全局第三方服务配置
func (this *apiComp) UpdateGlobalConfig(session comm.IUserSession, req *pb.ApiUpdateGlobalConfigReq) (resp *pb.ApiUpdateGlobalConfigResp, errdata *pb.ErrorData) {
	var (
		err error
	)
	if err = this.module.model.updateglobalconfig(req.Config); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("UpdateGlobalConfig Fail!", log.Field{Key: "uid", Value: session.GetUserId()}, log.Field{Key: "err", Value: err.Error()})
		return
	}
	if err = this.service.RpcBroadcast(session, comm.Service_Home, string(comm.Rpc_ModifyAppConifg), &pb.Rpc_EmptyReq{}, nil); err != nil {
		this.module.Error("广播失败了!", log.Field{Key: "err", Value: err.Error()})
	}
	resp = &pb.ApiUpdateGlobalConfigResp{}
	return
}
