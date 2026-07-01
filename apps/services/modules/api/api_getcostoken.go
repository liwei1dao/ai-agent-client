package api

import (
	"yunyan/comm"
	"yunyan/pb"
	"yunyan/sys/tencentyun/cos"
)

// 获取COS临时上传凭证（前端直传用）
func (this *apiComp) GetCosToken(session comm.IUserSession, req *pb.ApiGetCosTokenReq) (resp *pb.ApiGetCosTokenResp, errdata *pb.ErrorData) {
	result, err := cos.Sts()
	if err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_SystemError,
			Message: "获取上传凭证失败: " + err.Error(),
		}
		return
	}
	config := cos.GetConfig()
	resp = &pb.ApiGetCosTokenResp{
		Bucket:       config.BucketName,
		Region:       config.Region,
		BucketUrl:    config.BucketURL,
		TmpSecretId:  result.Credentials.TmpSecretID,
		TmpSecretKey: result.Credentials.TmpSecretKey,
		SessionToken: result.Credentials.SessionToken,
		Expiration:   result.Expiration,
		Domain:       config.DomainName,
	}
	return
}
