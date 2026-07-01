package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// 登录后台
func (this *apiComp) DelChannelApp(session comm.IUserSession, req *pb.ApiDelChannelAppReq) (resp *pb.ApiDelChannelAppResp, errdata *pb.ErrorData) {
	var (
		err error
	)
	if err = this.module.model.delchannelapp(req.Channel); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("登录失败!", log.Field{Key: "uid", Value: session.GetUserId()}, log.Field{Key: "err", Value: err.Error()})
		return
	}
	resp = &pb.ApiDelChannelAppResp{}
	return
}
