package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// 登录后台
func (this *apiComp) GetPayOrders(session comm.IUserSession, req *pb.ApiGetPayOrdersReq) (resp *pb.ApiGetPayOrdersResp, errdata *pb.ErrorData) {
	var (
		where  string
		args   []interface{}
		orders []*pb.DBPayOrder
		total  int64
		err    error
	)
	if req.Uid != "" {
		where = "uid=?"
		args = append(args, req.Uid)
	}
	if req.Status != -1 {
		if where != "" {
			where += " and "
		}
		where += "status=?"
		args = append(args, req.Status)
	}
	if req.Start != 0 {
		if where != "" {
			where += " and "
		}
		where += "create_time>=?"
		args = append(args, req.Start)
	}
	if req.End != 0 {
		if where != "" {
			where += " and "
		}
		where += "create_time<=?"
		args = append(args, req.End)
	}

	page := req.Page
	if page <= 0 {
		page = 1
	}
	size := req.Size
	if size <= 0 {
		size = 20
	}

	if orders, total, err = this.module.model.getPayOrders(where, page, size, args...); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("登录失败!", log.Field{Key: "uid", Value: session.GetUserId()}, log.Field{Key: "err", Value: err.Error()})
		return
	}
	resp = &pb.ApiGetPayOrdersResp{
		Orders: orders,
		Total:  total,
	}
	return
}
