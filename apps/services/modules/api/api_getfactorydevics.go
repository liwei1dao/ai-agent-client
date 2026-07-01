package api

import (
	"fmt"
	"strings"

	"yunyan/comm"
	"yunyan/pb"
)

// 获取授权码列表（支持按 usedtime/createtime 排序、分页）
func (this *apiComp) GetFactoryDevics(session comm.IUserSession, req *pb.ApiGetFactoryDevicsReq) (resp *pb.ApiGetFactoryDevicsResp, errdata *pb.ErrorData) {
	var (
		query  string
		args   []interface{}
		models []*pb.DBFactoryDevics
		total  int64
		err    error
	)
	if req.Productid == 0 {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_ReqParameterError,
			Message: "productid 不能为空",
		}
		return
	}

	conds := make([]string, 0, 7)
	if req.Code != "" {
		conds = append(conds, "code=?")
		args = append(args, req.Code)
	}
	if req.Devicemac != "" {
		conds = append(conds, "devicemac=?")
		args = append(args, req.Devicemac)
	}
	if req.Factoryid != 0 {
		conds = append(conds, "factoryid=?")
		args = append(args, req.Factoryid)
	}
	if req.Probatch != 0 {
		conds = append(conds, "probatch=?")
		args = append(args, req.Probatch)
	}
	// status: -1 表示「仅未使用」, 1 表示「已使用」, 2 表示「已过期」, 0 表示不筛选
	switch req.Status {
	case -1:
		conds = append(conds, "status=?")
		args = append(args, 0)
	case 1, 2:
		conds = append(conds, "status=?")
		args = append(args, req.Status)
	}
	if req.Uid != "" {
		conds = append(conds, "uid=?")
		args = append(args, req.Uid)
	}
	if len(conds) > 0 {
		query = strings.Join(conds, " and ")
	}

	sortBy := strings.ToLower(strings.TrimSpace(req.Sortby))
	if sortBy != "usedtime" && sortBy != "createtime" {
		sortBy = "createtime"
	}
	order := strings.ToLower(strings.TrimSpace(req.Order))
	if order != "asc" {
		order = "desc"
	}
	limit := int(req.Limit)
	if limit <= 0 {
		limit = 200
	}
	if limit > 2000 {
		limit = 2000
	}
	offset := int(req.Offset)
	if offset < 0 {
		offset = 0
	}
	orderClause := fmt.Sprintf("%s %s", sortBy, order)

	if models, total, err = this.module.model.factoryDevicsPaged(req.Productid, query, orderClause, limit, offset, args...); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		return
	}
	resp = &pb.ApiGetFactoryDevicsResp{
		Devices: models,
		Total:   total,
	}
	return
}
