package api

// import (
// 	"yunyan/comm"
// 	"yunyan/pb"
// )

// // 获取配置
// func (this *apiComp) GetAuthCode(session comm.IUserSession, req *pb.ApiGetAuthCodeReq) (resp *pb.ApiGetAuthCodeResp, errdata *pb.ErrorData) {
// 	var (
// 		model *pb.DBAuthCode
// 		err   error
// 	)

// 	if model, err = this.module.model.authcode(req.Code); err != nil {
// 		errdata = &pb.ErrorData{
// 			Code:    pb.ErrorCode_DBError,
// 			Message: err.Error(),
// 		}
// 		return
// 	}
// 	resp = &pb.ApiGetAuthCodeResp{
// 		Authcode: model,
// 	}
// 	return
// }
