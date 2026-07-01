package api

import (
	"yunyan/comm"
	"yunyan/pb"
	"yunyan/sys/email"
	"os"
	"strings"
)

// 上传设备升级包
func (this *apiComp) Sendsmtpemail(session comm.IUserSession, req *pb.ApiSendsmtpemailReq) (resp *pb.ApiSendsmtpemailResp, errdata *pb.ErrorData) {

	var (
		filename, filePath string
		file               *os.File
		err                error
	)
	filename = session.GetMateToString("file_name")
	filePath = session.GetMateToString("file_path")
	defer os.Remove(filePath)
	if file, err = os.Open(filePath); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_ReqParameterError,
			Message: pb.ErrorCode_ReqParameterError.String(),
		}
		return
	}
	defer file.Close()
	to := strings.Split(req.To, ",")
	if req.Cc != "" {
		to = append(to, strings.Split(req.Cc, ",")...)
	}
	if req.Bcc != "" {
		to = append(to, strings.Split(req.Bcc, ",")...)
	}

	if err = email.SendMailForFile(req.Subject, req.Content, filePath, filename, to...); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_ReqParameterError,
			Message: pb.ErrorCode_ReqParameterError.String(),
		}
	}
	resp = &pb.ApiSendsmtpemailResp{}
	return
}
