package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// normalizeAdminScope 按身份规整权限字段：
//   - 超管/管理员：全部权限、不受工厂/产品限制，access/factoryids/productids 一律置空
//   - 运营/代理：按前端勾选保留 access/factoryids/productids
func normalizeAdminScope(identity pb.Identity, access, factoryids, productids string) (string, string, string) {
	if identity == pb.Identity_Admin || identity == pb.Identity_Manager {
		return "", "", ""
	}
	return access, factoryids, productids
}

// 添加管理员账号
func (this *apiComp) AddAdminUser(session comm.IUserSession, req *pb.ApiAddAdminUserReq) (resp *pb.ApiAddAdminUserResp, errdata *pb.ErrorData) {
	if req.Account == "" || req.Password == "" {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_ReqParameterError, Message: "account and password required"}
		return
	}
	// 管理员不受工厂/产品白名单限制，强制清空
	access, factoryids, productids := normalizeAdminScope(req.Identity, req.Access, req.Factoryids, req.Productids)
	user := &pb.DBAdminUser{
		Account:    req.Account,
		Password:   req.Password,
		Identity:   req.Identity,
		Access:     access,
		Factoryids: factoryids,
		Productids: productids,
	}
	if err := this.module.model.addAdminUser(user); err != nil {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_DBError, Message: err.Error()}
		this.module.Error("AddAdminUser", log.Field{Key: "err", Value: err.Error()})
		return
	}
	resp = &pb.ApiAddAdminUserResp{}
	return
}

// 删除管理员账号
func (this *apiComp) DelAdminUser(session comm.IUserSession, req *pb.ApiDelAdminUserReq) (resp *pb.ApiDelAdminUserResp, errdata *pb.ErrorData) {
	if req.Account == "" {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_ReqParameterError, Message: "account required"}
		return
	}
	if err := this.module.model.delAdminUser(req.Account); err != nil {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_DBError, Message: err.Error()}
		this.module.Error("DelAdminUser", log.Field{Key: "err", Value: err.Error()})
		return
	}
	resp = &pb.ApiDelAdminUserResp{}
	return
}

// 修改管理员账号
func (this *apiComp) UpdateAdminUser(session comm.IUserSession, req *pb.ApiUpdateAdminUserReq) (resp *pb.ApiUpdateAdminUserResp, errdata *pb.ErrorData) {
	if req.Account == "" {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_ReqParameterError, Message: "account required"}
		return
	}
	user, err := this.module.model.findforaccount(req.Account)
	if err != nil {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_UserSessionNobeing, Message: err.Error()}
		return
	}
	if req.Password != "" {
		user.Password = req.Password
	}
	if req.Identity != pb.Identity_Identity_Null {
		user.Identity = req.Identity
	}
	// 管理员不受工厂/产品白名单限制，强制清空；运营/代理按本次提交覆盖
	user.Access, user.Factoryids, user.Productids = normalizeAdminScope(user.Identity, req.Access, req.Factoryids, req.Productids)
	if err = this.module.model.updateAdminUser(user); err != nil {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_DBError, Message: err.Error()}
		this.module.Error("UpdateAdminUser", log.Field{Key: "err", Value: err.Error()})
		return
	}
	resp = &pb.ApiUpdateAdminUserResp{}
	return
}

// 查询管理员账号列表
func (this *apiComp) GetAdminUsers(session comm.IUserSession, req *pb.ApiGetAdminUsersReq) (resp *pb.ApiGetAdminUsersResp, errdata *pb.ErrorData) {
	users, err := this.module.model.getAdminUsers()
	if err != nil {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_DBError, Message: err.Error()}
		this.module.Error("GetAdminUsers", log.Field{Key: "err", Value: err.Error()})
		return
	}
	resp = &pb.ApiGetAdminUsersResp{Users: users}
	return
}
