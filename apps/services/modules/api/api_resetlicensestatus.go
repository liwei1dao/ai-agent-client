package api

import (
	"yunyan/comm"
	"yunyan/pb"
)

// 重置License状态（单条）
func (this *apiComp) ResetLicenseStatus(session comm.IUserSession, req *pb.ApiResetLicenseStatusReq) (resp *pb.ApiResetLicenseStatusResp, errdata *pb.ErrorData) {
	if err := this.resetOneLicense(req.License); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		return
	}
	resp = &pb.ApiResetLicenseStatusResp{}
	return
}
