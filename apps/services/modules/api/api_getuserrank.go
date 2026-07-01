package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// GetUserRank 用户使用量排行查询
// 仪表盘和代理仪表盘共用：管理员/站长 看到全平台，代理也看到全平台但额外标记自己名下用户。
// 代理可传 product_id 把"我的"标记限定为该产品下的绑定用户；0 或非代理身份忽略此过滤。
// @Summary 查询用户使用量排行
// @Description 翻译/会议两类用量 Top N，可选标记当前账号名下用户
// @Tags API
// @Accept json
// @Produce json
// @Param user body pb.ApiGetUserRankReq true "查询请求"
// @Success 200 {object} comm.HttpResult{data=pb.ApiGetUserRankResp} "成功"
// @Router /web/api/api_getuserrank [post]
func (this *apiComp) GetUserRank(session comm.IUserSession, req *pb.ApiGetUserRankReq) (resp *pb.ApiGetUserRankResp, errdata *pb.ErrorData) {
	limit := int(req.Limit)
	if limit <= 0 || limit > 100 {
		limit = 10
	}

	var (
		rows []*userRankRow
		err  error
	)
	switch req.Type {
	case "meet":
		rows, err = this.module.model.topUserRankByMeet(limit)
	default:
		rows, err = this.module.model.topUserRankByTrade(limit)
	}
	if err != nil {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_DBError, Message: err.Error()}
		this.module.Error("GetUserRank query fail", log.Field{Key: "err", Value: err.Error()})
		return
	}

	resp = &pb.ApiGetUserRankResp{List: make([]*pb.UserRankItem, 0, len(rows))}
	if len(rows) == 0 {
		return
	}

	uids := make([]string, 0, len(rows))
	for _, r := range rows {
		uids = append(uids, r.Uid)
	}

	users, err := this.module.model.findUsersByUids(uids)
	if err != nil {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_DBError, Message: err.Error()}
		this.module.Error("GetUserRank find users fail", log.Field{Key: "err", Value: err.Error()})
		return
	}

	// 代理身份：按 product_id 过滤"我的"标记集合
	agentUidSet := make(map[string]struct{})
	if pb.Identity(session.GetMateToInt32("identity")) == pb.Identity_Agent {
		scope := this.getSessionScope(session)
		allProducts, perr := this.module.model.products()
		if perr == nil {
			var pids []uint32
			if req.ProductId > 0 {
				visible := visibleProductIDs(scope, allProducts)
				inScope := scope.Unlimited
				for _, v := range visible {
					if v == req.ProductId {
						inScope = true
						break
					}
				}
				if inScope {
					pids = []uint32{req.ProductId}
				}
			} else {
				pids = visibleProductIDs(scope, allProducts)
			}
			if len(pids) > 0 {
				if agentUids, derr := this.module.model.agentDeviceUIDs(pids); derr == nil {
					for _, u := range agentUids {
						agentUidSet[u] = struct{}{}
					}
				}
			}
		}
	}

	for _, r := range rows {
		item := &pb.UserRankItem{
			Uid:        r.Uid,
			TradeTime:  r.TradeTime,
			TradeCount: r.TradeCount,
			MeetTime:   r.MeetTime,
			MeetCount:  r.MeetCount,
		}
		if u, ok := users[r.Uid]; ok && u != nil {
			item.Nickname = u.Name
			item.Avatar = u.Avatar
			item.CountryCode = u.CountryCode
		}
		if _, ok := agentUidSet[r.Uid]; ok {
			item.IsAgentUser = true
		}
		resp.List = append(resp.List, item)
	}
	return
}
