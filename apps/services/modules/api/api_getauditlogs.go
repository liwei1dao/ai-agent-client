package api

import (
	"yunyan/comm"
	"yunyan/pb"
)

// 查询操作日志
// 超管看全部，管理员和代理只能看自己的
func (this *apiComp) GetConsoleLogs(session comm.IUserSession, req *pb.ApiGetConsoleLogsReq) (resp *pb.ApiGetConsoleLogsResp, errdata *pb.ErrorData) {
	query := "1=1"
	args := make([]interface{}, 0)

	// 非超管只能查自己的日志
	identity := session.GetMateToString("identity")
	if identity != "1" {
		query += " AND account = ?"
		args = append(args, session.GetUserId())
	} else if req.Account != "" {
		// 超管可以按账号筛选
		query += " AND account = ?"
		args = append(args, req.Account)
	}

	if req.ApiName != "" {
		query += " AND api_name = ?"
		args = append(args, req.ApiName)
	}
	if req.Code > 0 {
		query += " AND code = ?"
		args = append(args, req.Code)
	} else if req.Code == 0 {
		// code=0 不筛选（proto默认值），用 -1 表示只查成功
	}

	limit := int(req.Limit)
	if limit <= 0 || limit > 500 {
		limit = 200
	}
	query += " ORDER BY created_at DESC LIMIT ?"
	args = append(args, limit)

	logs, err := this.module.modelAudit.getConsoleLogs(query, args...)
	if err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		return
	}
	resp = &pb.ApiGetConsoleLogsResp{
		Logs: logs,
	}
	return
}

// 获取操作日志筛选项（下拉列表数据）
func (this *apiComp) GetConsoleLogFilters(session comm.IUserSession, req *pb.ApiGetConsoleLogFiltersReq) (resp *pb.ApiGetConsoleLogFiltersResp, errdata *pb.ErrorData) {
	resp = &pb.ApiGetConsoleLogFiltersResp{}

	accounts, err := this.module.modelAudit.getDistinctAccounts()
	if err != nil {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_DBError, Message: err.Error()}
		return
	}

	apiNames, err := this.module.modelAudit.getDistinctApiNames()
	if err != nil {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_DBError, Message: err.Error()}
		return
	}

	// 非超管只返回自己的账号
	identity := session.GetMateToString("identity")
	if identity != "1" {
		resp.Accounts = []string{session.GetUserId()}
	} else {
		resp.Accounts = accounts
	}
	resp.ApiNames = apiNames
	return
}
