package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// 登录后台
func (this *apiComp) GetAgent(session comm.IUserSession, req *pb.ApiGetAgentReq) (resp *pb.ApiGetAgentResp, errdata *pb.ErrorData) {
	var (
		agent *pb.DBAgent
		err   error
	)

	if agent, err = this.module.model.agent(req.Id); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("登录失败!", log.Field{Key: "uid", Value: session.GetUserId()}, log.Field{Key: "err", Value: err.Error()})
		return
	}
	resp = &pb.ApiGetAgentResp{
		Agent: agent,
	}
	return
}
