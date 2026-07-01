package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// 登录后台
func (this *apiComp) GetGoodss(session comm.IUserSession, req *pb.ApiDelGoodsReq) (resp *pb.ApiGetGoodssResp, errdata *pb.ErrorData) {
	var (
		goods []*pb.DBGoods
		err   error
	)

	if goods, err = this.module.model.goodss(); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("GetGoodss 失败!", log.Field{Key: "uid", Value: session.GetUserId()}, log.Field{Key: "err", Value: err.Error()})
		return
	}
	resp = &pb.ApiGetGoodssResp{
		Goodss: goods,
	}
	return
}
