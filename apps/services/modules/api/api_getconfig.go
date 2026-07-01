package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// 获取配置
func (this *apiComp) GetConfig(session comm.IUserSession, req *pb.ApiGetConfigReq) (resp *pb.ApiGetConfigResp, errdata *pb.ErrorData) {
	var (
		config []*pb.DBAppConfigItem
		err    error
	)

	if config, err = this.module.model.config(); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("登录失败!", log.Field{Key: "uid", Value: session.GetUserId()}, log.Field{Key: "err", Value: err.Error()})
		return
	}
	resp = &pb.ApiGetConfigResp{
		Config: config,
	}
	return
}
