package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// 获取配置
func (this *apiComp) GetFactory(session comm.IUserSession, req *pb.ApiGetFactoryReq) (resp *pb.ApiGetFactoryResp, errdata *pb.ErrorData) {
	var (
		model *pb.DBFactory
		err   error
	)

	if model, err = this.module.model.factory(req.Id); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("登录失败!", log.Field{Key: "uid", Value: session.GetUserId()}, log.Field{Key: "err", Value: err.Error()})
		return
	}
	resp = &pb.ApiGetFactoryResp{
		Factory: model,
	}
	return
}
