package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// 新增唤醒语音
func (this *apiComp) AddWakeupVoice(session comm.IUserSession, req *pb.ApiAddWakeupVoiceReq) (resp *pb.ApiAddWakeupVoiceResp, errdata *pb.ErrorData) {
	var (
		err error
	)
	if err = this.module.model.addwakeupvoice(req.Voice); err != nil {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_DBError, Message: err.Error()}
		this.module.Error("AddWakeupVoice 失败!", log.Field{Key: "uid", Value: session.GetUserId()}, log.Field{Key: "err", Value: err.Error()})
		return
	}
	resp = &pb.ApiAddWakeupVoiceResp{}
	return
}
