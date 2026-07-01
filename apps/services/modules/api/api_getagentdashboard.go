package api

import (
	"yunyan/comm"
	"yunyan/pb"
)

// GetAgentDashboard 代理仪表盘统计
// 仅代理身份（identity=3）可调用，返回其名下生产、激活、绑定、充值等汇总数据。
// 支持按 product_id 切换：0=代理全部产品汇总；指定 productid 时仅统计该产品（且产品需在代理可见范围内）。
func (this *apiComp) GetAgentDashboard(session comm.IUserSession, req *pb.ApiGetAgentDashboardReq) (resp *pb.ApiGetAgentDashboardResp, errdata *pb.ErrorData) {
	scope := this.getSessionScope(session)

	allProducts, err := this.module.model.products()
	if err != nil {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_DBError, Message: err.Error()}
		return
	}

	// 代理可见的产品（用于下拉与统计范围基线）
	visibleProds := visibleProductIDs(scope, allProducts)
	visibleSet := make(map[uint32]struct{}, len(visibleProds))
	for _, id := range visibleProds {
		visibleSet[id] = struct{}{}
	}

	var (
		productIDs []uint32
		factoryIDs []uint32
	)
	if req.ProductId > 0 {
		// 校验：所选产品必须在代理可见范围内
		if _, ok := visibleSet[req.ProductId]; !ok && !scope.Unlimited {
			errdata = &pb.ErrorData{Code: pb.ErrorCode_InsufficientPermissions, Message: "无权访问该产品"}
			return
		}
		// 锁定到具体产品时，不再用 factoryid 兜底，避免同厂其它产品被算进来
		productIDs = []uint32{req.ProductId}
		factoryIDs = nil
	} else {
		productIDs = visibleProds
		// 若代理已显式配置 ProductIDs，则统计严格按产品白名单进行；
		// 不再附加 factoryIDs，避免 batch 统计走 "factoryid IN ?" 把同厂下未勾选的产品也带进来。
		if len(scope.ProductIDs) > 0 {
			factoryIDs = nil
		} else {
			factoryIDs = visibleFactoryIDs(scope, allProducts)
		}
	}

	resp = &pb.ApiGetAgentDashboardResp{}

	// 1. 生产批次 & 设备码总量
	batchCount, deviceCount, err := this.module.model.agentBatchStats(factoryIDs, productIDs)
	if err != nil {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_DBError, Message: err.Error()}
		return
	}
	resp.BatchCount = batchCount
	resp.DeviceCount = deviceCount

	// 2. 激活数 & 绑定用户：读取「重建统计」时落库的 product_stat 快照
	//    （rebuildProductStats 全量扫描 userdevice 生成；点击后台“重建统计数据”刷新）。
	activatedCount, boundUserCount, err := this.module.model.sumProductStats(productIDs)
	if err != nil {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_DBError, Message: err.Error()}
		return
	}
	resp.ActivatedCount = activatedCount
	resp.BoundUserCount = boundUserCount

	// 名下用户 uid 列表：充值 / 消耗统计需按当前 userdevice 实时获取
	uids, err := this.module.model.agentDeviceUIDs(productIDs)
	if err != nil {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_DBError, Message: err.Error()}
		return
	}

	// 3. 充值统计
	orderCount, totalAmount, err := this.module.model.agentPayStats(uids)
	if err != nil {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_DBError, Message: err.Error()}
		return
	}
	resp.PayOrderCount = orderCount
	resp.PayTotalAmount = totalAmount

	// 4. 名下用户累计消耗
	tradeTime, tradeCount, meetTime, meetCount, err := this.module.model.agentUsageStats(uids)
	if err != nil {
		errdata = &pb.ErrorData{Code: pb.ErrorCode_DBError, Message: err.Error()}
		return
	}
	resp.TradeTime = tradeTime
	resp.TradeCount = tradeCount
	resp.MeetTime = meetTime
	resp.MeetCount = meetCount

	// 5. 资源点池（按当前账号读取）
	account := session.GetMateToString(comm.SessionMeta_UserId)
	if account != "" {
		if u, ferr := this.module.model.findforaccount(account); ferr == nil && u != nil {
			resp.VipdayBalance = u.VipdayBalance
			resp.AichatintegralBalance = u.AichatintegralBalance
			resp.TradesecondBalance = u.TradesecondBalance
			resp.MeetsecondBalance = u.MeetsecondBalance
		}
		if rv, ra, rt, rm, rerr := this.module.model.sumAdminReceivedResource(account); rerr == nil {
			resp.TotalReceivedVipday = rv
			resp.TotalReceivedAichatintegral = ra
			resp.TotalReceivedTradesecond = rt
			resp.TotalReceivedMeetsecond = rm
		}
		if dv, da, dt, dm, derr := this.module.model.sumAdminDispatchedResource(account); derr == nil {
			resp.TotalDispatchedVipday = dv
			resp.TotalDispatchedAichatintegral = da
			resp.TotalDispatchedTradesecond = dt
			resp.TotalDispatchedMeetsecond = dm
		}
	}

	// 6. 代理可切换的产品列表（下拉）
	resp.Products = make([]*pb.AgentProductItem, 0, len(visibleProds))
	for _, p := range allProducts {
		if scope.Unlimited {
			resp.Products = append(resp.Products, &pb.AgentProductItem{
				Id: p.Id, Devicename: p.Devicename, Factoryid: p.Factoryid,
			})
			continue
		}
		if _, ok := visibleSet[p.Id]; ok {
			resp.Products = append(resp.Products, &pb.AgentProductItem{
				Id: p.Id, Devicename: p.Devicename, Factoryid: p.Factoryid,
			})
		}
	}
	return
}
