package api

import (
	"yunyan/comm"
	"yunyan/pb"
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v4"
)

// 登录后台
func (this *apiComp) Login(session comm.IUserSession, req *pb.ApiLoginReq) (resp *pb.ApiLoginResp, errdata *pb.ErrorData) {
	var (
		model       *pb.DBAdminUser
		tokenString string
		err         error
	)
	if model, err = this.module.model.findforaccount(req.Account); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_UserSessionNobeing,
			Message: "账号不存在",
		}
		return
	}
	if model.Password != req.Password {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_ReqParameterError,
			Message: "密码错误",
		}
		return
	}
	claims := &jwt.RegisteredClaims{
		Issuer:    this.service.GetTag(),
		Subject:   fmt.Sprintf("%d", model.Identity),
		ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Hour * 24)), // 24 hours expiration
		NotBefore: jwt.NewNumericDate(time.Now()),
		IssuedAt:  jwt.NewNumericDate(time.Now()),
		ID:        model.Account,
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	if tokenString, err = token.SignedString([]byte(this.options.TokenKey)); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_ReqParameterError,
			Message: pb.ErrorCode_ReqParameterError.String(),
		}
		this.module.Errorln(err)
		return
	}
	resp = &pb.ApiLoginResp{
		Account:    model.Account,
		Identity:   model.Identity,
		Access:     model.Access,
		Token:      tokenString,
		Avatar:     "https://gw.alipayobjects.com/zos/rmsportal/BiazfanxmamNRoxxVxka.png",
		Factoryids: model.Factoryids,
		Productids: model.Productids,
	}
	return
}
