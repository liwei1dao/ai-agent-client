package api

import (
	"yunyan/comm"
	"yunyan/pb"
)

// 上传设备升级包
func (this *apiComp) UploadChannelApp(session comm.IUserSession, req *pb.ApiUploadChannelAppReq) (resp *pb.ApiUploadChannelAppResp, errdata *pb.ErrorData) {

	var (
		err error
	)

	if err = this.module.model.updatechannelapp(req.App); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: pb.ErrorCode_DBError.String(),
		}
		return
	}
	resp = &pb.ApiUploadChannelAppResp{}
	return
}
