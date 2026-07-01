package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// 获取配置
func (this *apiComp) GetProducts(session comm.IUserSession, req *pb.ApiGetProductsReq) (resp *pb.ApiGetProductsResp, errdata *pb.ErrorData) {
	var (
		models []*pb.DBProduct
		err    error
	)

	if models, err = this.module.model.products(); err != nil {
		errdata = &pb.ErrorData{
			Code:    pb.ErrorCode_DBError,
			Message: err.Error(),
		}
		this.module.Error("登录失败!", log.Field{Key: "uid", Value: session.GetUserId()}, log.Field{Key: "err", Value: err.Error()})
		return
	}

	// 运营/代理：按账号的 factoryids + productids 白名单过滤
	scope := this.getSessionScope(session)
	if !scope.Unlimited {
		allowed := visibleProductIDs(scope, models)
		allowSet := make(map[uint32]struct{}, len(allowed))
		for _, id := range allowed {
			allowSet[id] = struct{}{}
		}
		filtered := make([]*pb.DBProduct, 0, len(models))
		for _, p := range models {
			if _, ok := allowSet[p.Id]; ok {
				filtered = append(filtered, p)
			}
		}
		models = filtered
	}

	resp = &pb.ApiGetProductsResp{
		Products: models,
	}
	return
}
