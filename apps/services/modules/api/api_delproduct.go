package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// 登录后台
func (this *apiComp) DelProduct(session comm.IUserSession, req *pb.ApiDelProductReq) (resp *pb.ApiDelProductResp, errdata *pb.ErrorData) {
	var (
		err error
	)
	if err = this.module.model.delproducts(req.Id); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("登录失败!", log.Field{Key: "uid", Value: session.GetUserId()}, log.Field{Key: "err", Value: err.Error()})
		return
	}
	resp = &pb.ApiDelProductResp{}
	return
}
