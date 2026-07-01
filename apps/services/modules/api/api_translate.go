package api

import (
	"context"
	"yunyan/comm"
	"yunyan/pb"
	"yunyan/sys/microsoft/translate"
)

// 翻译接口（后台管理用）
func (this *apiComp) Translate(session comm.IUserSession, req *pb.ApiTranslateReq) (resp *pb.ApiTranslateResp, errdata *pb.ErrorData) {
	results, err := translate.Translate(context.Background(), req.From, req.To, req.Texts)
	if err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_SystemError,
			Message: "翻译失败: " + err.Error(),
		}
		return
	}
	resp = &pb.ApiTranslateResp{
		Results: results,
	}
	return
}
