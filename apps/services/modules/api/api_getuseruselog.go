package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
	"strings"
)

// GetUserUseLogs 查询用户使用量日志
// @Summary 查询用户使用量日志
// @Description 查询用户使用量日志
// @Tags API
// @Accept json
// @Produce json
// @Param user body pb.ApiGetUserUseLogsReq true "查询请求"
// @Success 200 {object} comm.HttpResult{data=pb.ApiGetUserUseLogsResp} "成功"
// @Router /web/api/api_getuseruselogs [post]
func (this *apiComp) GetUserUseLogs(session comm.IUserSession, req *pb.ApiGetUserUseLogsReq) (resp *pb.ApiGetUserUseLogsResp, errdata *pb.ErrorData) {
	var (
		query      string
		args       []interface{}
		conditions []string
		logs       []*pb.DBUserUseLog
		err        error
	)

	// 动态构建查询条件
	if req.Uid != "" {
		conditions = append(conditions, "uid = ?")
		args = append(args, req.Uid)
	}

	if req.Usagetype != pb.UserLogType_UserLogTypeUnknown {
		conditions = append(conditions, "logtype = ?")
		args = append(args, req.Usagetype)
	}

	if req.Start > 0 {
		conditions = append(conditions, "ts >= ?")
		args = append(args, req.Start)
	}

	if req.End > 0 {
		conditions = append(conditions, "ts <= ?")
		args = append(args, req.End)
	}

	if len(conditions) > 0 {
		query = strings.Join(conditions, " AND ")
	}

	if logs, err = this.module.model.getUserUseLog(query, args...); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("GetUserUseLogs 失败!", log.Field{Key: "uid", Value: session.GetUserId()}, log.Field{Key: "err", Value: err.Error()})
		return
	}
	resp = &pb.ApiGetUserUseLogsResp{
		Logs: logs,
	}
	return
}
