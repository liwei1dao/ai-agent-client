package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// 登录后台
func (this *apiComp) UpdateMcpServers(session comm.IUserSession, req *pb.ApiUpdateMcpServersReq) (resp *pb.ApiUPdateMcpServerResp, errdata *pb.ErrorData) {
	var (
		err error
	)
	if err = this.module.model.updatemcpservers(req.Servers); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("登录失败!", log.Field{Key: "uid", Value: session.GetUserId()}, log.Field{Key: "err", Value: err.Error()})
		return
	}
	if err = this.service.RpcBroadcast(session, comm.Service_Home, string(comm.Rpc_ModifyAppConifg), &pb.Rpc_EmptyReq{}, nil); err != nil {
		this.module.Error("广播失败了!", log.Field{Key: "err", Value: err.Error()})
	}
	resp = &pb.ApiUPdateMcpServerResp{}
	return
}
