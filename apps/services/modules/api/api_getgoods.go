package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// 登录后台
func (this *apiComp) GetGoods(session comm.IUserSession, req *pb.ApiGetGoodsReq) (resp *pb.ApiGetGoodsResp, errdata *pb.ErrorData) {
	var (
		goods *pb.DBGoods
		err   error
	)

	if goods, err = this.module.model.goods(req.Id); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("GetGoods 失败!", log.Field{Key: "uid", Value: session.GetUserId()}, log.Field{Key: "err", Value: err.Error()})
		return
	}
	resp = &pb.ApiGetGoodsResp{
		Goods: goods,
	}
	return
}
