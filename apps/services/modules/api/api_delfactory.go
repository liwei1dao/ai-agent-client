package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// 删除厂商
func (this *apiComp) DelFactory(session comm.IUserSession, req *pb.ApiDelFactoryReq) (resp *pb.ApiDelFactoryResp, errdata *pb.ErrorData) {
	var (
		err error
	)
	if err = this.module.model.delfactory(req.Id); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("DelEquipment Fail!", log.Field{Key: "req", Value: req.String()}, log.Field{Key: "err", Value: err.Error()})
		return
	}
	resp = &pb.ApiDelFactoryResp{}
	return
}
