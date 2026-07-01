package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// 查询App综合统计数据（日/月/年）
func (this *apiComp) GetAppStats(session comm.IUserSession, req *pb.ApiGetAppStatsReq) (resp *pb.ApiGetAppStatsResp, errdata *pb.ErrorData) {
	var (
		stats []*pb.DBAppStat
		err   error
	)
	if req.StatType == 0 {
		req.StatType = 1 // 默认日统计
	}
	if stats, err = this.module.model.getAppStats(req.StatType, req.StartDate, req.EndDate); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("GetAppStats fail", log.Field{Key: "uid", Value: session.GetUserId()}, log.Field{Key: "err", Value: err.Error()})
		return
	}
	resp = &pb.ApiGetAppStatsResp{Stats: stats}
	return
}
