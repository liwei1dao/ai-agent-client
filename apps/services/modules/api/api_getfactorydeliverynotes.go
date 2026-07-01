package api

import (
	"yunyan/comm"
	"yunyan/pb"
)

// 查询生产出货单（生产设备码日志统计）
func (this *apiComp) GetFactoryDeliveryNotes(session comm.IUserSession, req *pb.ApiGetFactoryDeliveryNotesReq) (resp *pb.ApiGetFactoryDeliveryNotesResp, errdata *pb.ErrorData) {
	query := "1=1"
	args := make([]interface{}, 0)

	if req.Factoryid > 0 {
		query += " AND factoryid = ?"
		args = append(args, req.Factoryid)
	}
	if req.Productid > 0 {
		query += " AND productid = ?"
		args = append(args, req.Productid)
	}
	if req.Start > 0 {
		query += " AND ts >= ?"
		args = append(args, req.Start)
	}
	if req.End > 0 {
		query += " AND ts <= ?"
		args = append(args, req.End)
	}

	limit := int(req.Limit)
	if limit <= 0 || limit > 2000 {
		limit = 500
	}
	query += " ORDER BY ts DESC LIMIT ?"
	args = append(args, limit)

	notes, err := this.module.model.factorydeliverynotes(query, args...)
	if err != nil {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_DBError, Message: err.Error()}
		return
	}

	var totalDevices int64
	for _, n := range notes {
		totalDevices += int64(n.Devicetnum)
	}

	resp = &pb.ApiGetFactoryDeliveryNotesResp{
		Notes:        notes,
		TotalBatch:   int64(len(notes)),
		TotalDevices: totalDevices,
	}
	return
}
