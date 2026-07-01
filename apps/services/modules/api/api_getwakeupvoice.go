package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// 获取唤醒语音列表
func (this *apiComp) GetWakeupVoice(session comm.IUserSession, req *pb.ApiGetWakeupVoiceReq) (resp *pb.ApiGetWakeupVoiceResp, errdata *pb.ErrorData) {
	var (
		model *pb.DBWakeupVoice
		err   error
	)

	if model, err = this.module.model.wakeupvoice(req.Id); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("GetWakeupVoice 失败!", log.Field{Key: "uid", Value: session.GetUserId()}, log.Field{Key: "err", Value: err.Error()})
		return
	}
	resp = &pb.ApiGetWakeupVoiceResp{
		Voice: model,
	}
	return
}
