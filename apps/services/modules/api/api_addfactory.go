package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
	"strings"
)

const defaultFactoryContactMail = "358030594@qq.com"

// 添加配置
func (this *apiComp) AddFactory(session comm.IUserSession, req *pb.ApiAddFactoryReq) (resp *pb.ApiAddFactoryResp, errdata *pb.ErrorData) {
	var (
		err error
	)
	if req.Factory != nil {
		req.Factory.Contactmails = ensureDefaultContactMail(req.Factory.Contactmails)
	}
	if err = this.module.model.addfactory(req.Factory); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("AddFactory Fail!", log.Field{Key: "req", Value: req.String()}, log.Field{Key: "err", Value: err.Error()})
		return
	}

	resp = &pb.ApiAddFactoryResp{
		Factory: req.Factory,
	}
	return
}

// 确保厂家联系邮箱中包含默认邮箱
func ensureDefaultContactMail(mails string) string {
	parts := strings.Split(mails, ",")
	cleaned := make([]string, 0, len(parts)+1)
	has := false
	for _, p := range parts {
		m := strings.TrimSpace(p)
		if m == "" {
			continue
		}
		if strings.EqualFold(m, defaultFactoryContactMail) {
			has = true
		}
		cleaned = append(cleaned, m)
	}
	if !has {
		cleaned = append([]string{defaultFactoryContactMail}, cleaned...)
	}
	return strings.Join(cleaned, ",")
}
