package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// 登录后台
func (this *apiComp) UpdateGoods(session comm.IUserSession, req *pb.ApiUpdateGoodsReq) (resp *pb.ApiUpdateGoodsResp, errdata *pb.ErrorData) {
	var (
		err error
	)
	if err = this.module.model.updategoods(req.Goods); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("UpdateGoods 失败!", log.Field{Key: "uid", Value: session.GetUserId()}, log.Field{Key: "err", Value: err.Error()})
		return
	}
	resp = &pb.ApiUpdateGoodsResp{}
	return
}
