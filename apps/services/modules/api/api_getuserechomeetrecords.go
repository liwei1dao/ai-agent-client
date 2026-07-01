package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// GetUserEchomeetRecords 查询指定用户的会议记录列表
func (this *apiComp) GetUserEchomeetRecords(session comm.IUserSession, req *pb.ApiGetUserEchomeetRecordsReq) (resp *pb.ApiGetUserEchomeetRecordsResp, errdata *pb.ErrorData) {
	records, err := this.module.model.getUserEchomeetRecords(req.Uid, req.Start, req.End)
	if err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("查询用户会议记录失败", log.Field{Key: "uid", Value: req.Uid}, log.Field{Key: "err", Value: err.Error()})
		return
	}
	resp = &pb.ApiGetUserEchomeetRecordsResp{
		Records: records,
	}
	return
}
