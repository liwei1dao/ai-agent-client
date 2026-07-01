package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// GetUserUseLogsPaged 用户资源流水分页查询
// - 默认按类型筛选 + 分页（管理员/代理赠送=AdminGive、绑定设备赠送=ActivityReward、充值获取=Pay、消耗=UserConsume）；
// - 代理身份强制锁定为「仅当前代理赠送出去的流水」，即 logtype=AdminGive 且 extra=当前账号，前端类型筛选不可切换。
func (this *apiComp) GetUserUseLogsPaged(session comm.IUserSession, req *pb.ApiGetUserUseLogsPagedReq) (resp *pb.ApiGetUserUseLogsPagedResp, errdata *pb.ErrorData) {
	uid := req.Uid
	logtype := req.Logtype
	operator := ""

	identity := pb.Identity(session.GetMateToInt32("identity"))
	if identity == pb.Identity_Agent {
		// 代理只能看自己派发的资源流水
		operator = session.GetMateToString(comm.SessionMeta_UserId)
		logtype = pb.UserLogType_AdminGive
	}

	logs, total, err := this.module.model.getUserUseLogsPaged(uid, logtype, operator, req.Page, req.Size)
	if err != nil {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_DBError, Message: err.Error()}
		this.module.Error("GetUserUseLogsPaged fail", log.Field{Key: "err", Value: err.Error()})
		return
	}
	resp = &pb.ApiGetUserUseLogsPagedResp{Logs: logs, Total: total}
	return
}
