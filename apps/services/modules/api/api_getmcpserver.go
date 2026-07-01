package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// 登录后台
func (this *apiComp) GetMcpServer(session comm.IUserSession, req *pb.ApiGetMcpServerReq) (resp *pb.ApiGetMcpServerResp, errdata *pb.ErrorData) {
	var (
		server *pb.DBMcpServer
		err    error
	)

	if server, err = this.module.model.mcpserver(req.Id); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("登录失败!", log.Field{Key: "uid", Value: session.GetUserId()}, log.Field{Key: "err", Value: err.Error()})
		return
	}
	resp = &pb.ApiGetMcpServerResp{
		Server: server,
	}
	return
}
