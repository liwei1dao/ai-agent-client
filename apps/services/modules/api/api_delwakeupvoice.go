package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// 删除唤醒语音
func (this *apiComp) DelWakeupVoice(session comm.IUserSession, req *pb.ApiDelWakeupVoiceReq) (resp *pb.ApiDelWakeupVoiceResp, errdata *pb.ErrorData) {
	var (
		err error
	)
	if err = this.module.model.delwakeupvoice(req.Id); err != nil {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_DBError, Message: err.Error()}
		this.module.Error("DelWakeupVoice 失败!", log.Field{Key: "uid", Value: session.GetUserId()}, log.Field{Key: "err", Value: err.Error()})
		return
	}
	resp = &pb.ApiDelWakeupVoiceResp{}
	return
}
