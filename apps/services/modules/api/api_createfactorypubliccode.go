package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
	"time"
)

// 创建厂家公码（一厂家可多码，每次调用生成一条新码）
// 公码字符串自动随机生成 6 位短码，遇到极端碰撞时重试若干次
func (this *apiComp) CreateFactoryPublicCode(session comm.IUserSession, req *pb.ApiCreateFactoryPublicCodeReq) (resp *pb.ApiCreateFactoryPublicCodeResp, errdata *pb.ErrorData) {
	var (
		code  string
		err   error
		now   = time.Now().Unix()
		model *pb.DBFactoryPublicCode
	)

	if req.Factoryid == 0 {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_ReqParameterError,
			Message: "factoryid 必填",
		}
		return
	}

	// 校验厂家存在
	if _, err = this.module.model.factory(req.Factoryid); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: "厂家不存在: " + err.Error(),
		}
		return
	}

	// 防碰撞：32^6 ≈ 10亿，正常一次成功；最多重试 5 次
	for i := 0; i < 5; i++ {
		if code, err = comm.GeneratePublicCode(); err != nil {
			errdata = &pb.ErrorData{
				Code:    pb.ErrorCode_SystemError,
				Message: err.Error(),
			}
			return
		}
		if _, e := this.module.model.factoryPublicCode(code); e != nil {
			// 不存在 → 可以用
			break
		}
		code = ""
	}
	if code == "" {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_SystemError,
			Message: "公码生成多次碰撞，请重试",
		}
		return
	}

	model = &pb.DBFactoryPublicCode{
		Code:                code,
		Factoryid:           req.Factoryid,
		Productid:           req.Productid,
		Remark:              req.Remark,
		Status:              0,
		Maxuses:             req.Maxuses,
		Useduses:            0,
		Expiretime:          req.Expiretime,
		Bindrewardvpitime:   req.Bindrewardvpitime,
		Bindrewardtranslate: req.Bindrewardtranslate,
		Bindrewardmeeting:   req.Bindrewardmeeting,
		Createtime:          now,
		Updatetime:          now,
	}

	if err = this.module.model.addFactoryPublicCode(model); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("CreateFactoryPublicCode Fail!", log.Field{Key: "err", Value: err.Error()})
		return
	}

	resp = &pb.ApiCreateFactoryPublicCodeResp{Code: model}
	return
}
