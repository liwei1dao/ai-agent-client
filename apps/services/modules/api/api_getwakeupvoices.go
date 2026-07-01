package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// 获取唤醒语音列表
func (this *apiComp) GetWakeupVoices(session comm.IUserSession, req *pb.ApiGetWakeupVoicesReq) (resp *pb.ApiGetWakeupVoicesResp, errdata *pb.ErrorData) {
	var (
		models []*pb.DBWakeupVoice
		err    error
	)

	if models, err = this.module.model.wakeupvoices(); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("GetWakeupVoices 失败!", log.Field{Key: "uid", Value: session.GetUserId()}, log.Field{Key: "err", Value: err.Error()})
		return
	}
	resp = &pb.ApiGetWakeupVoicesResp{
		Voices: models,
	}
	return
}
