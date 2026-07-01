package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// GetGlobalStats 查询全局累计统计
// @Summary 查询全局累计统计
// @Description 返回生命周期累计的 App 综合统计，以及实时计算的累计注册/充值人数
// @Tags API
// @Accept json
// @Produce json
// @Param user body pb.ApiGetGlobalStatsReq true "查询请求"
// @Success 200 {object} comm.HttpResult{data=pb.ApiGetGlobalStatsResp} "成功"
// @Router /web/api/api_getglobalstats [post]
func (this *apiComp) GetGlobalStats(session comm.IUserSession, req *pb.ApiGetGlobalStatsReq) (resp *pb.ApiGetGlobalStatsResp, errdata *pb.ErrorData) {
	var (
		stat         *pb.DBAppStat
		totalUsers   int64
		totalPayUser int64
		err          error
	)
	if stat, err = this.module.model.getGlobalStat(); err != nil {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_DBError, Message: err.Error()}
		this.module.Error("GetGlobalStats fail", log.Field{Key: "err", Value: err.Error()})
		return
	}
	if totalUsers, err = this.module.model.countTotalUsers(); err != nil {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_DBError, Message: err.Error()}
		this.module.Error("countTotalUsers fail", log.Field{Key: "err", Value: err.Error()})
		return
	}
	if totalPayUser, err = this.module.model.countTotalPayUsers(); err != nil {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_DBError, Message: err.Error()}
		this.module.Error("countTotalPayUsers fail", log.Field{Key: "err", Value: err.Error()})
		return
	}
	resp = &pb.ApiGetGlobalStatsResp{
		Stat:              stat,
		TotalUserCount:    totalUsers,
		TotalPayUserCount: totalPayUser,
	}
	return
}
