package api

// // 创建授权码
// func (this *apiComp) CreateAuthCode(session comm.IUserSession, req *pb.ApiCreateAuthCodesReq) (resp *pb.ApiCreateAuthCodesResp, errdata *pb.ErrorData) {
// 	var (
// 		err          error
// 		modelFactory *pb.DBFactory
// 		code         string
// 		models       []*pb.DBAuthCode = make([]*pb.DBAuthCode, 0, req.Number)
// 	)

// 	if modelFactory, err = this.module.model.factory(uint32(req.Factoryid)); err != nil {
// 		errdata = &pb.ErrorData{
// 			Code:    pb.ErrorCode_DBError,
// 			Message: err.Error(),
// 		}
// 		return
// 	}
// 	modelFactory.Probatch++
// 	for i := 1; i <= int(req.Number); i++ {
// 		if code, err = GenerateLicense(uint16(req.Productid), byte(modelFactory.Probatch), uint32(i)); err != nil {
// 			errdata = &pb.ErrorData{
// 				Code:    pb.ErrorCode_SystemError,
// 				Message: err.Error(),
// 			}
// 			return
// 		}
// 		models = append(models, &pb.DBAuthCode{
// 			Code:       code,
// 			Productid:  req.Productid,
// 			Factoryid:  req.Factoryid,
// 			Probatch:   modelFactory.Probatch,
// 			Number:     uint32(i),
// 			Createtime: time.Now().Unix(),
// 		})
// 	}
// 	if err = this.module.model.addauthcodes(models); err != nil {
// 		errdata = &pb.ErrorData{
// 			Code:    pb.ErrorCode_DBError,
// 			Message: err.Error(),
// 		}
// 		this.module.Error("addauthcodes Fail!", log.Field{Key: "err", Value: err.Error()})
// 		return
// 	}
// 	if err = this.module.model.savefactory(modelFactory); err != nil {
// 		errdata = &pb.ErrorData{
// 			Code:    pb.ErrorCode_DBError,
// 			Message: err.Error(),
// 		}
// 		this.module.Error("savefactory Fail!", log.Field{Key: "err", Value: err.Error()})
// 		return
// 	}
// 	resp = &pb.ApiCreateAuthCodesResp{
// 		Authcodes: models,
// 	}
// 	return
// }
