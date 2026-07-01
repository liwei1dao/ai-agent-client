package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// 登录后台
func (this *apiComp) GetUser(session comm.IUserSession, req *pb.ApiGetUserReq) (resp *pb.ApiGetUserResp, errdata *pb.ErrorData) {
	var (
		model *pb.DBUser
		err   error
	)

	if req.Searchtype == 0 {

		if model, err = this.module.model.finduser(req.Searchvalue); err != nil {
			errdata = &pb.ErrorData{
				Code:    pb.ErrorCode_DBError,
				Message: err.Error(),
			}
			this.module.Error("登录失败!", log.Field{Key: "uid", Value: session.GetUserId()}, log.Field{Key: "err", Value: err.Error()})
			return
		}
	} else if req.Searchtype == 1 {

		if model, err = this.module.model.finduserbyphone(req.Searchvalue); err != nil {
			errdata = &pb.ErrorData{
				Code:    pb.ErrorCode_DBError,
				Message: err.Error(),
			}
			this.module.Error("登录失败!", log.Field{Key: "uid", Value: session.GetUserId()}, log.Field{Key: "err", Value: err.Error()})
			return
		}
	} else if req.Searchtype == 2 {
		if model, err = this.module.model.finduserbyemail(req.Searchvalue); err != nil {
			errdata = &pb.ErrorData{
				Code:    pb.ErrorCode_DBError,
				Message: err.Error(),
			}
			this.module.Error("登录失败!", log.Field{Key: "uid", Value: session.GetUserId()}, log.Field{Key: "err", Value: err.Error()})
			return
		}
	}
	resp = &pb.ApiGetUserResp{
		User: model,
	}
	return
}
