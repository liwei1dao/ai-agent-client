package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// 登录后台
func (this *apiComp) GetAgents(session comm.IUserSession, req *pb.ApiGetAgentsReq) (resp *pb.ApiGetAgentsResp, errdata *pb.ErrorData) {
	var (
		agents []*pb.DBAgent
		err    error
	)

	if agents, err = this.module.model.agents(); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("登录失败!", log.Field{Key: "uid", Value: session.GetUserId()}, log.Field{Key: "err", Value: err.Error()})
		return
	}
	resp = &pb.ApiGetAgentsResp{
		Agents: agents,
	}
	return
}
