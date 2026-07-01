package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
	"fmt"
)

// 添加配置
func (this *apiComp) AddProduct(session comm.IUserSession, req *pb.ApiAddProductReq) (resp *pb.ApiAddProductResp, errdata *pb.ErrorData) {
	var (
		factory *pb.DBFactory
		err     error
	)
	if req.Product.Bassfilter > 1000 {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_ReqParameterError,
			Message: "bassfilter 取值范围为 0-1000",
		}
		return
	}
	if factory, err = this.module.model.factory(req.Product.Factoryid); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("AddProduct!", log.Field{Key: "uid", Value: session.GetUserId()}, log.Field{Key: "err", Value: err.Error()})
		return
	}
	if err = this.module.model.addproducts(req.Product); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("AddProduct!", log.Field{Key: "uid", Value: session.GetUserId()}, log.Field{Key: "err", Value: err.Error()})
		return
	}
	if len(factory.Productlists) == 0 {
		factory.Productlists = fmt.Sprintf("%d", req.Product.Id)
	} else {
		factory.Productlists = fmt.Sprintf("%s,%d", factory.Productlists, req.Product.Id)
	}
	if err = this.module.model.savefactory(factory); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("AddProduct!", log.Field{Key: "uid", Value: session.GetUserId()}, log.Field{Key: "err", Value: err.Error()})
		return
	}
	if err = this.service.RpcBroadcast(session, comm.Service_Home, string(comm.Rpc_ModifyAppConifg), &pb.Rpc_EmptyReq{}, nil); err != nil {
		this.module.Error("AddProduct!", log.Field{Key: "err", Value: err.Error()})
	}
	resp = &pb.ApiAddProductResp{
		Product: req.Product,
	}
	return
}
