package api

import (
	"yunyan/comm"
	"yunyan/pb"
)

// 获取配置
func (this *apiComp) GetFactoryDevic(session comm.IUserSession, req *pb.ApiGetFactoryDevicReq) (resp *pb.ApiGetFactoryDevicResp, errdata *pb.ErrorData) {
	var (
		model *pb.DBFactoryDevics
		err   error
	)

	if model, err = this.module.model.factoryDevic(req.Productid, req.Devicemac); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		return
	}
	resp = &pb.ApiGetFactoryDevicResp{
		Device: model,
	}
	return
}
