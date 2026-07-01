package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// 添加支付商品
func (this *apiComp) AddGoods(session comm.IUserSession, req *pb.ApiAddGoodsReq) (resp *pb.ApiAddGoodsResp, errdata *pb.ErrorData) {
	var (
		err error
	)
	if err = this.module.model.addgoods(req.Goods); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("添加支付商品失败!", log.Field{Key: "uid", Value: session.GetUserId()}, log.Field{Key: "err", Value: err.Error()})
		return
	}
	resp = &pb.ApiAddGoodsResp{}
	return
}
