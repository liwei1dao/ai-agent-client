package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// 添加配置
func (this *apiComp) AddProductVersion(session comm.IUserSession, req *pb.ApiAddProductVersionReq) (resp *pb.ApiAddProductVersionResp, errdata *pb.ErrorData) {
	var (
		model *pb.DBProduct
		err   error
	)
	if err = this.module.model.addproductversion(req.Version); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("操作失败!", log.Field{Key: "uid", Value: session.GetUserId()}, log.Field{Key: "err", Value: err.Error()})
		return
	}
	if req.Isuse {
		if model, err = this.module.model.product(req.Version.Productid); err != nil {
			errdata = &pb.ErrorData{
				Code:    pb.ErrorCode_DBError,
				Message: err.Error(),
			}
			this.module.Error("操作失败!", log.Field{Key: "uid", Value: session.GetUserId()}, log.Field{Key: "err", Value: err.Error()})
			return
		}
		model.Version = req.Version.Version
		model.Updatedescription = req.Version.Description
		model.Updatepackageaddress = req.Version.Updatepackageaddress
		model.Versionid = req.Version.Id
	}
	resp = &pb.ApiAddProductVersionResp{
		Version: req.Version,
	}
	return
}
