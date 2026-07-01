package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// 查询厂家公码列表
// factoryid=0 返回全部；status<0 不过滤状态
func (this *apiComp) GetFactoryPublicCodes(session comm.IUserSession, req *pb.ApiGetFactoryPublicCodesReq) (resp *pb.ApiGetFactoryPublicCodesResp, errdata *pb.ErrorData) {
	models, err := this.module.model.factoryPublicCodes(req.Factoryid, req.Status)
	if err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("GetFactoryPublicCodes Fail!", log.Field{Key: "err", Value: err.Error()})
		return
	}
	resp = &pb.ApiGetFactoryPublicCodesResp{Codes: models}
	return
}
