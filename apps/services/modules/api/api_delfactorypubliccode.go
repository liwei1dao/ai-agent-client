package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// 删除厂家公码
// 仅删除公码本身；已领取记录(DBUserPublicCodeRedeem)保留以维持防重复领的全局唯一性约束
func (this *apiComp) DelFactoryPublicCode(session comm.IUserSession, req *pb.ApiDelFactoryPublicCodeReq) (resp *pb.ApiDelFactoryPublicCodeResp, errdata *pb.ErrorData) {
	if req.Code == "" {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_ReqParameterError,
			Message: "code 必填",
		}
		return
	}
	if err := this.module.model.delFactoryPublicCode(req.Code); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("DelFactoryPublicCode Fail!", log.Field{Key: "err", Value: err.Error()})
		return
	}
	resp = &pb.ApiDelFactoryPublicCodeResp{}
	return
}
