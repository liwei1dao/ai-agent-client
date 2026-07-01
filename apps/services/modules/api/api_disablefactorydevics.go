package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// DisableFactoryDevics 批量禁用/恢复设备码：
// disabled = -1 禁用（绑定时会被拒绝），disabled = 0 恢复正常。
func (this *apiComp) DisableFactoryDevics(session comm.IUserSession, req *pb.ApiDisableFactoryDevicsReq) (resp *pb.ApiDisableFactoryDevicsResp, errdata *pb.ErrorData) {
	if req.Productid == 0 || len(req.Codes) == 0 {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_ReqParameterError,
			Message: "productid/codes 不能为空",
		}
		return
	}
	// 只接受 0(正常) 或 -1(禁用) 两个合法值
	disabled := int32(0)
	if req.Disabled != 0 {
		disabled = -1
	}

	affected, err := this.module.model.setFactoryDevicsDisabled(req.Productid, req.Codes, disabled)
	if err != nil {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_DBError, Message: err.Error()}
		this.module.Error("DisableFactoryDevics Fail!", log.Field{Key: "err", Value: err.Error()})
		return
	}

	this.module.Info("DisableFactoryDevics ok",
		log.Field{Key: "operator", Value: session.GetUserId()},
		log.Field{Key: "productid", Value: req.Productid},
		log.Field{Key: "disabled", Value: disabled},
		log.Field{Key: "count", Value: len(req.Codes)},
		log.Field{Key: "affected", Value: affected})

	resp = &pb.ApiDisableFactoryDevicsResp{Affected: affected}
	return
}
