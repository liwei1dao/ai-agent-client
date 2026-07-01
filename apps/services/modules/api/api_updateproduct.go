package api

import (
	"yunyan/comm"
	"yunyan/pb"
)

// 更新产品
func (this *apiComp) UpdateProduct(session comm.IUserSession, req *pb.ApiUpdateProductReq) (resp *pb.ApiUpdateProductResp, errdata *pb.ErrorData) {
	var err error

	if req.Product.Bassfilter > 1000 {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_ReqParameterError,
			Message: "bassfilter 取值范围为 0-1000",
		}
		return
	}

	if _, err = this.module.model.product(req.Product.Id); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_ReqParameterError,
			Message: pb.ErrorCode_ReqParameterError.String(),
		}
		return
	}

	// 指定了 versionid 时，从版本表同步版本/描述/升级包地址，前端无需重复传
	if req.Product.Versionid != 0 {
		ver, verr := this.module.model.productversion(req.Product.Versionid)
		if verr != nil || ver == nil || ver.Productid != req.Product.Id {
			errdata = &pb.ErrorData{
				Code:    pb.ErrorCode_ReqParameterError,
				Message: "versionid 无效",
			}
			return
		}
		req.Product.Version = ver.Version
		req.Product.Updatedescription = ver.Description
		req.Product.Updatepackageaddress = ver.Updatepackageaddress
	}

	if err = this.module.model.updateproducts(req.Product); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: pb.ErrorCode_DBError.String(),
		}
		return
	}
	resp = &pb.ApiUpdateProductResp{}
	return
}
