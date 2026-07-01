package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// 添加会议模板
func (this *apiComp) AddTemplates(session comm.IUserSession, req *pb.ApiAddTemplatesReq) (resp *pb.ApiAddTemplateResp, errdata *pb.ErrorData) {
	var (
		err error
	)
	for _, v := range req.Templates {
		v.Source = "public"
	}
	if err = this.module.model.addtemplates(req.Templates); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("AddTemplate失败!", log.Field{Key: "uid", Value: session.GetUserId()}, log.Field{Key: "err", Value: err.Error()})
		return
	}
	if err = this.service.RpcBroadcast(session, comm.Service_Home, string(comm.Rpc_ModifyAppConifg), &pb.Rpc_EmptyReq{}, nil); err != nil {
		this.module.Error("广播失败了!", log.Field{Key: "err", Value: err.Error()})
	}
	if err = this.service.RpcBroadcast(session, comm.Service_Home, string(comm.Rpc_ModifyEchomeetTemplate), &pb.Rpc_EmptyReq{}, nil); err != nil {
		this.module.Error("广播失败了!", log.Field{Key: "err", Value: err.Error()})
	}
	resp = &pb.ApiAddTemplateResp{}
	return
}
