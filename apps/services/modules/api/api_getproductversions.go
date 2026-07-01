package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// 获取配置
func (this *apiComp) GetProductVersions(session comm.IUserSession, req *pb.ApiGetProductVersionsReq) (resp *pb.ApiGetProductVersionsResp, errdata *pb.ErrorData) {
	var (
		models []*pb.DBProductVersion
		err    error
	)

	if models, err = this.module.model.productversions(req.Pid); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("登录失败!", log.Field{Key: "uid", Value: session.GetUserId()}, log.Field{Key: "err", Value: err.Error()})
		return
	}
	resp = &pb.ApiGetProductVersionsResp{
		Versions: models,
	}
	return
}
