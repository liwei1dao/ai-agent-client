package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// 获取全局第三方服务配置
func (this *apiComp) GetGlobalConfig(session comm.IUserSession, req *pb.ApiGetGlobalConfigReq) (resp *pb.ApiGetGlobalConfigResp, errdata *pb.ErrorData) {
	var (
		config []*pb.DBGlobalConfigItem
		err    error
	)
	if config, err = this.module.model.globalconfigbyregion(req.Region); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("GetGlobalConfig Fail!", log.Field{Key: "uid", Value: session.GetUserId()}, log.Field{Key: "err", Value: err.Error()})
		return
	}
	resp = &pb.ApiGetGlobalConfigResp{
		Config: config,
	}
	return
}
