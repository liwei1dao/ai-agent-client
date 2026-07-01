package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// RevokeFactoryDevics 撤销一个生产批次：
// 1. 校验出货单存在；
// 2. 该批次中若已有任意一个设备码被使用（status>0 或 uid 非空），拒绝撤销；
// 3. 删除该批次全部设备码 + 删除出货单记录。
//
// 注意：不回退 factory.probatch（已分发出去的批次号不应重复利用，避免与历史导出的批次冲突）。
func (this *apiComp) RevokeFactoryDevics(session comm.IUserSession, req *pb.ApiRevokeFactoryDevicsReq) (resp *pb.ApiRevokeFactoryDevicsResp, errdata *pb.ErrorData) {
	if req.Factoryid == 0 || req.Productid == 0 || req.Probatch == 0 {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_ReqParameterError,
			Message: "factoryid/productid/probatch 不能为空",
		}
		return
	}

	note, err := this.module.model.factorydeliverynote(req.Factoryid, req.Probatch)
	if err != nil || note == nil || note.Productid != req.Productid {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: "未找到指定生产批次",
		}
		return
	}

	used, err := this.module.model.countUsedFactoryDevicsByBatch(req.Productid, req.Probatch)
	if err != nil {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_DBError, Message: err.Error()}
		this.module.Error("RevokeFactoryDevics count used Fail!", log.Field{Key: "err", Value: err.Error()})
		return
	}
	if used > 0 {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_ReqParameterError,
			Message: "该批次已有设备码被激活/绑定，无法撤销",
		}
		return
	}

	affected, err := this.module.model.delfactoryDevicsByBatch(req.Productid, req.Probatch)
	if err != nil {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_DBError, Message: err.Error()}
		this.module.Error("RevokeFactoryDevics delete devics Fail!", log.Field{Key: "err", Value: err.Error()})
		return
	}

	if err = this.module.model.delfactorydeliverynote(req.Factoryid, req.Productid, req.Probatch); err != nil {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_DBError, Message: err.Error()}
		this.module.Error("RevokeFactoryDevics delete delivery note Fail!", log.Field{Key: "err", Value: err.Error()})
		return
	}

	this.module.Info("RevokeFactoryDevics ok",
		log.Field{Key: "operator", Value: session.GetUserId()},
		log.Field{Key: "factoryid", Value: req.Factoryid},
		log.Field{Key: "productid", Value: req.Productid},
		log.Field{Key: "probatch", Value: req.Probatch},
		log.Field{Key: "deleted", Value: affected})

	resp = &pb.ApiRevokeFactoryDevicsResp{Deleted: uint32(affected)}
	return
}
