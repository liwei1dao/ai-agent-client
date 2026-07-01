package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
	"time"
)

// GrantAdminResource 超管→后台账号 赠送资源点
// 仅超管（Admin）可调用；接收账号必须存在；接收的资源点会累加到目标账号的池中，
// 同时写入 admin_resource_log 用于流水审计。
func (this *apiComp) GrantAdminResource(session comm.IUserSession, req *pb.ApiGrantAdminResourceReq) (resp *pb.ApiGrantAdminResourceResp, errdata *pb.ErrorData) {
	if req.Account == "" {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_ReqParameterError, Message: "account required"}
		return
	}
	if req.Vipday <= 0 && req.Aichatintegral <= 0 && req.Tradesecond <= 0 && req.Meetsecond <= 0 {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_ReqParameterError, Message: "至少填写一项资源"}
		return
	}
	target, err := this.module.model.findforaccount(req.Account)
	if err != nil || target == nil {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_UserSessionNobeing, Message: "目标账号不存在"}
		return
	}
	if target.Identity == pb.Identity_Admin {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_ReqParameterError, Message: "无需向超管赠送资源"}
		return
	}
	// 用原子 UPDATE (col = col + ?) 直接调整余额，避免 Save 全字段覆盖时其它字段不一致，
	// 也避免并发赠送/派发互相覆盖。
	if _, err = this.module.model.adjustAdminBalance(req.Account, req.Vipday, req.Aichatintegral, req.Tradesecond, req.Meetsecond); err != nil {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_DBError, Message: err.Error()}
		this.module.Error("GrantAdminResource adjust balance fail", log.Field{Key: "account", Value: req.Account}, log.Field{Key: "err", Value: err.Error()})
		return
	}
	// 重读返回最新行
	if target, err = this.module.model.findforaccount(req.Account); err != nil {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_DBError, Message: err.Error()}
		return
	}
	from := session.GetMateToString(comm.SessionMeta_UserId)
	flowLog := &pb.DBAdminResourceLog{
		Ts:             time.Now().Unix(),
		FromAccount:    from,
		ToAccount:      req.Account,
		Vipday:         req.Vipday,
		Aichatintegral: req.Aichatintegral,
		Tradesecond:    req.Tradesecond,
		Meetsecond:     req.Meetsecond,
		Remark:         req.Remark,
	}
	if err = this.module.model.addAdminResourceLog(flowLog); err != nil {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_DBError, Message: err.Error()}
		this.module.Error("GrantAdminResource add log fail", log.Field{Key: "err", Value: err.Error()})
		return
	}
	resp = &pb.ApiGrantAdminResourceResp{User: target}
	return
}
