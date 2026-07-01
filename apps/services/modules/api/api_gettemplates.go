package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// 登录后台
func (this *apiComp) GetTemplates(session comm.IUserSession, req *pb.ApiGetTemplatesReq) (resp *pb.ApiGetTemplatesResp, errdata *pb.ErrorData) {
	var (
		models []*pb.DBEchoMeetTemplate
		err    error
	)
	if models, err = this.module.model.gettemplates(); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("ApiGetTemplates失败!", log.Field{Key: "uid", Value: session.GetUserId()}, log.Field{Key: "err", Value: err.Error()})
		return
	}
	resp = &pb.ApiGetTemplatesResp{
		Templates: models,
	}
	return
}
