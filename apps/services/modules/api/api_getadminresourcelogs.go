package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// GetAdminResourceLogs 后台账号资源流水查询（超管→后台账号）
// - 超管：可查全部，可按 account 过滤；
// - 其他身份：固定只能看到与自己相关（from 或 to）的流水（即使前端不传 account，也会被强制改为自己）。
func (this *apiComp) GetAdminResourceLogs(session comm.IUserSession, req *pb.ApiGetAdminResourceLogsReq) (resp *pb.ApiGetAdminResourceLogsResp, errdata *pb.ErrorData) {
	identity := pb.Identity(session.GetMateToInt32("identity"))
	account := req.Account
	if identity != pb.Identity_Admin {
		account = session.GetMateToString(comm.SessionMeta_UserId)
	}
	logs, total, err := this.module.model.getAdminResourceLogs(account, req.Page, req.Size)
	if err != nil {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_DBError, Message: err.Error()}
		this.module.Error("GetAdminResourceLogs fail", log.Field{Key: "err", Value: err.Error()})
		return
	}
	resp = &pb.ApiGetAdminResourceLogsResp{Logs: logs, Total: total}
	return
}
