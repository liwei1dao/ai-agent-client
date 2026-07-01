package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// 更新唤醒语音
func (this *apiComp) UpdateWakeupVoice(session comm.IUserSession, req *pb.ApiUpdateWakeupVoiceReq) (resp *pb.ApiUpdateWakeupVoiceResp, errdata *pb.ErrorData) {
	var (
		err error
	)
	if err = this.module.model.updatewakeupvoice(req.Voice); err != nil {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_DBError, Message: err.Error()}
		this.module.Error("UpdateWakeupVoice 失败!", log.Field{Key: "uid", Value: session.GetUserId()}, log.Field{Key: "err", Value: err.Error()})
		return
	}
	resp = &pb.ApiUpdateWakeupVoiceResp{}
	return
}
