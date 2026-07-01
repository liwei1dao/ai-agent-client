package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// 重置设备状态
func (this *apiComp) RestFactoryDevics(session comm.IUserSession, req *pb.ApiRestUserDevicsReq) (resp *pb.ApiRestUserDevicsResp, errdata *pb.ErrorData) {
	var (
		models []*pb.DBFactoryDevics

		err error
	)
	if err = this.module.model.deluserdevice(req.Uid); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("RestFactoryDevics Fail!", log.Field{Key: "uid", Value: session.GetUserId()}, log.Field{Key: "err", Value: err.Error()})
		return
	}
	if models, err = this.module.model.factoryDevicforuid(req.Productid, req.Uid); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("RestFactoryDevics Fail!", log.Field{Key: "uid", Value: session.GetUserId()}, log.Field{Key: "err", Value: err.Error()})
		return
	}

	for _, models := range models {
		models.Status = 0 // 重置状态
		models.Uid = ""
		models.Devicemac = ""
	}
	if err = this.module.model.updatefactoryDevics(req.Productid, models); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("RestFactoryDevics Fail!", log.Field{Key: "uid", Value: session.GetUserId()}, log.Field{Key: "err", Value: err.Error()})
		return
	}

	resp = &pb.ApiRestUserDevicsResp{}
	return
}
