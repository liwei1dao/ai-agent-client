package api

// // 获取配置
// func (this *apiComp) GetAuthCodes(session comm.IUserSession, req *pb.ApiGetAuthCodesReq) (resp *pb.ApiGetAuthCodesResp, errdata *pb.ErrorData) {
// 	var (
// 		where  db.M
// 		models []*pb.DBAuthCode
// 		err    error
// 	)
// 	where = db.M{}
// 	if req.Code != "" {
// 		where["code"] = req.Code
// 	}
// 	if req.Productid != 0 {
// 		where["devicetype"] = req.Productid
// 	}
// 	if req.Factoryid != 0 {
// 		where["factoryid"] = req.Factoryid
// 	}
// 	if req.Probatch != 0 {
// 		where["probatch"] = req.Probatch
// 	}
// 	if req.Devicemac != "" {
// 		where["devicemac"] = req.Devicemac
// 	}
// 	if req.Status != 0 {
// 		where["status"] = req.Status
// 	}

// 	if req.Uid != "" {
// 		where["uid"] = req.Uid
// 	}

// 	if models, err = this.module.model.authcodes(where); err != nil {
// 		errdata = &pb.ErrorData{
// 			Code:    pb.ErrorCode_DBError,
// 			Message: err.Error(),
// 		}
// 		return
// 	}
// 	resp = &pb.ApiGetAuthCodesResp{
// 		Authcodes: models,
// 	}
// 	return
// }
