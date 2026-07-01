package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// 获取模板详情（含 outline / template 大文本）
func (this *apiComp) GetTemplate(session comm.IUserSession, req *pb.ApiGetTemplateReq) (resp *pb.ApiGetTemplateResp, errdata *pb.ErrorData) {
	var (
		model *pb.DBEchoMeetTemplate
		err   error
	)
	if model, err = this.module.model.gettemplate(req.Id); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("ApiGetTemplate失败!", log.Field{Key: "uid", Value: session.GetUserId()}, log.Field{Key: "id", Value: req.Id}, log.Field{Key: "err", Value: err.Error()})
		return
	}
	resp = &pb.ApiGetTemplateResp{
		Template: model,
	}
	return
}
