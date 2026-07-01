package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
	"time"
)

// 更新厂家公码（按 code 主键定位；保留 createtime/useduses/factoryid 不变）
func (this *apiComp) UpdateFactoryPublicCode(session comm.IUserSession, req *pb.ApiUpdateFactoryPublicCodeReq) (resp *pb.ApiUpdateFactoryPublicCodeResp, errdata *pb.ErrorData) {
	var (
		model *pb.DBFactoryPublicCode
		err   error
	)
	if req.Code == "" {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_ReqParameterError,
			Message: "code 必填",
		}
		return
	}
	if model, err = this.module.model.factoryPublicCode(req.Code); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: "公码不存在: " + err.Error(),
		}
		return
	}

	model.Productid = req.Productid
	model.Remark = req.Remark
	model.Status = req.Status
	model.Maxuses = req.Maxuses
	model.Expiretime = req.Expiretime
	model.Bindrewardvpitime = req.Bindrewardvpitime
	model.Bindrewardtranslate = req.Bindrewardtranslate
	model.Bindrewardmeeting = req.Bindrewardmeeting
	model.Updatetime = time.Now().Unix()

	if err = this.module.model.saveFactoryPublicCode(model); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("UpdateFactoryPublicCode Fail!", log.Field{Key: "err", Value: err.Error()})
		return
	}
	resp = &pb.ApiUpdateFactoryPublicCodeResp{Code: model}
	return
}
