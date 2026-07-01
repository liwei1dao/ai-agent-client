package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
	"time"
)

// 派发资源
// 规则：
//   - 超管（Admin）不受池余额限制，可无限派发；
//   - 其他后台账号（Manager/Agent/Operator）需先由超管赠送资源点至账号池，
//     派发时按本次额度从池中扣减；不足则拒绝。
func (this *apiComp) DispatchResource(session comm.IUserSession, req *pb.ApiDispatchResourceReq) (resp *pb.ApiDispatchResourceResp, errdata *pb.ErrorData) {
	var (
		user    *pb.DBUser
		userlog *pb.DBUserUseLog
		err     error
	)
	if user, err = this.module.model.finduser(req.Uid); err != nil {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_DBError, Message: err.Error()}
		this.module.Error("DispatchResource find user fail", log.Field{Key: "uid", Value: req.Uid}, log.Field{Key: "err", Value: err.Error()})
		return
	}

	addVipDay := int64(req.Vipday)
	addAichat := req.Aichatintegral
	addTradeSec := int64(req.Transtime) * 60
	addMeetSec := int64(req.Meettime) * 60
	if addVipDay <= 0 && addAichat <= 0 && addTradeSec <= 0 && addMeetSec <= 0 {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_ReqParameterError, Message: "至少填写一项资源"}
		return
	}

	// 当前操作账号 & 身份
	operator := session.GetMateToString(comm.SessionMeta_UserId)
	identity := pb.Identity(session.GetMateToInt32("identity"))

	// 非超管：需从池扣减
	var operatorUser *pb.DBAdminUser
	if identity != pb.Identity_Admin {
		if operator == "" {
			errdata = &pb.ErrorData{Code: pb.ErrorCode_NoLogin, Message: "登录信息异常"}
			return
		}
		if operatorUser, err = this.module.model.findforaccount(operator); err != nil || operatorUser == nil {
			errdata = &pb.ErrorData{Code: pb.ErrorCode_UserSessionNobeing, Message: "操作账号不存在"}
			return
		}
		if addVipDay > operatorUser.VipdayBalance ||
			addAichat > operatorUser.AichatintegralBalance ||
			addTradeSec > operatorUser.TradesecondBalance ||
			addMeetSec > operatorUser.MeetsecondBalance {
			errdata = &pb.ErrorData{Code: pb.ErrorCode_ResourceNotEnough, Message: "资源点余额不足"}
			return
		}
	}

	userlog = &pb.DBUserUseLog{
		Uid:     req.Uid,
		Logtype: pb.UserLogType_AdminGive,
		Ts:      time.Now().Unix(),
		Extra:   operator,
	}
	if addVipDay > 0 {
		addSeconds := addVipDay * 24 * 60 * 60
		if user.Vipexptime == 0 || user.Vipexptime < time.Now().Unix() {
			user.Vipexptime = time.Now().Unix() + addSeconds
		} else {
			user.Vipexptime = user.Vipexptime + addSeconds
		}
		userlog.Addvipday = addVipDay
	}
	if addAichat > 0 {
		user.Aichatintegral += addAichat
		user.Aichattotalintegral += addAichat
		userlog.Addagentintegral = addAichat
	}
	if addTradeSec > 0 {
		user.Tradeintegral += addTradeSec
		user.Tradetotalintegral += addTradeSec
		userlog.Addtradesecond = addTradeSec
	}
	if addMeetSec > 0 {
		user.Meetintegral += addMeetSec
		user.Meettotalintegral += addMeetSec
		userlog.Addmeetsecond = addMeetSec
	}
	if err = this.module.model.updateuser(user); err != nil {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_DBError, Message: err.Error()}
		this.module.Error("DispatchResource update user fail", log.Field{Key: "uid", Value: req.Uid}, log.Field{Key: "err", Value: err.Error()})
		return
	}
	if err = this.module.model.addIntegralLog(userlog); err != nil {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_DBError, Message: err.Error()}
		this.module.Error("DispatchResource add log fail", log.Field{Key: "uid", Value: req.Uid}, log.Field{Key: "err", Value: err.Error()})
		return
	}

	// 非超管：原子 UPDATE 扣减池余额（col = col - ?）。避免 Save 全字段覆盖时其它字段不一致，
	// 也避免与并发派发/赠送相互覆盖。
	if operatorUser != nil {
		if _, err = this.module.model.adjustAdminBalance(operator, -addVipDay, -addAichat, -addTradeSec, -addMeetSec); err != nil {
			errdata = &pb.ErrorData{Code: pb.ErrorCode_DBError, Message: err.Error()}
			this.module.Error("DispatchResource deduct pool fail", log.Field{Key: "operator", Value: operator}, log.Field{Key: "err", Value: err.Error()})
			return
		}
	}

	resp = &pb.ApiDispatchResourceResp{User: user}
	return
}
