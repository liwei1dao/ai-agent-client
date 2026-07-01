package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// 登录后台
func (this *apiComp) GetMcpServers(session comm.IUserSession, req *pb.ApiGetMcpServersReq) (resp *pb.ApiGetMcpServersResp, errdata *pb.ErrorData) {
	var (
		servers []*pb.DBMcpServer
		err     error
	)

	if servers, err = this.module.model.mcpservers(req.Region); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("登录失败!", log.Field{Key: "uid", Value: session.GetUserId()}, log.Field{Key: "err", Value: err.Error()})
		return
	}
	resp = &pb.ApiGetMcpServersResp{
		Servers: servers,
	}
	return
}
