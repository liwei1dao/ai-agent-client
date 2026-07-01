package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// 获取配置
func (this *apiComp) GetChannelApps(session comm.IUserSession, req *pb.ApiGetChannelAppsReq) (resp *pb.ApiGetChannelAppsResp, errdata *pb.ErrorData) {
	var (
		models []*pb.DBChannelApp
		err    error
	)

	if models, err = this.module.model.channelapps(); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("登录失败!", log.Field{Key: "uid", Value: session.GetUserId()}, log.Field{Key: "err", Value: err.Error()})
		return
	}
	resp = &pb.ApiGetChannelAppsResp{
		Apps: models,
	}
	return
}
