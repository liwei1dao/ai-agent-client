package api

import (
	"yunyan/comm"
	"yunyan/pb"
)

// GetMyAdminPool 返回当前登录账号的资源点池余额（含身份信息）
// 任意已登录后台账号均可调用；超管返回身份后前端可识别为"无需校验余额"。
func (this *apiComp) GetMyAdminPool(session comm.IUserSession, req *pb.ApiGetMyAdminPoolReq) (resp *pb.ApiGetMyAdminPoolResp, errdata *pb.ErrorData) {
	identity := pb.Identity(session.GetMateToInt32("identity"))
	resp = &pb.ApiGetMyAdminPoolResp{Identity: identity}
	if identity == pb.Identity_Admin {
		return
	}
	account := session.GetMateToString(comm.SessionMeta_UserId)
	if account == "" {
		return
	}
	if u, err := this.module.model.findforaccount(account); err == nil && u != nil {
		resp.VipdayBalance = u.VipdayBalance
		resp.AichatintegralBalance = u.AichatintegralBalance
		resp.TradesecondBalance = u.TradesecondBalance
		resp.MeetsecondBalance = u.MeetsecondBalance
	}
	return
}
