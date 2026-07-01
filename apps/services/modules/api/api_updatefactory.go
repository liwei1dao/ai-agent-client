package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// 更新厂家信息
func (this *apiComp) UpdateFactory(session comm.IUserSession, req *pb.ApiUpdateFactoryReq) (resp *pb.ApiUpdateFactoryResp, errdata *pb.ErrorData) {
	var (
		old *pb.DBFactory
		err error
	)
	if req.Factory == nil || req.Factory.Id == 0 {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_ReqParameterError,
			Message: "factory id is required",
		}
		return
	}
	if old, err = this.module.model.factory(req.Factory.Id); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("UpdateFactory Fail!", log.Field{Key: "req", Value: req.String()}, log.Field{Key: "err", Value: err.Error()})
		return
	}
	// 仅允许客户端覆盖可编辑字段，probatch / productlists 等由服务端维护的字段不接受前端写入，
	// 防止前端表单缺字段或携带陈旧值时把生产批次号、产品列表覆盖回旧值，导致后续生产撞批次撞码。
	old.Factory = req.Factory.Factory
	old.Factoryflag = req.Factory.Factoryflag
	old.Description = req.Factory.Description
	old.Contactmails = req.Factory.Contactmails
	if err = this.module.model.savefactory(old); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("UpdateFactory Fail!", log.Field{Key: "req", Value: req.String()}, log.Field{Key: "err", Value: err.Error()})
		return
	}

	resp = &pb.ApiUpdateFactoryResp{
		Factory: old,
	}
	return
}
