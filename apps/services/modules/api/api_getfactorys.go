package api

import (
	"yunyan/comm"
	"yunyan/lego/sys/log"
	"yunyan/pb"
)

// 获取配置
func (this *apiComp) GetFactorys(session comm.IUserSession, req *pb.ApiGetFactorysReq) (resp *pb.ApiGetFactorysResp, errdata *pb.ErrorData) {
	var (
		models []*pb.DBFactory
		err    error
	)

	if models, err = this.module.model.factorys(); err != nil {
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
		allProducts, _ := this.module.model.products()
		allowed := visibleFactoryIDs(scope, allProducts)
		allowSet := make(map[uint32]struct{}, len(allowed))
		for _, id := range allowed {
			allowSet[id] = struct{}{}
		}
		filtered := make([]*pb.DBFactory, 0, len(models))
		for _, f := range models {
			if _, ok := allowSet[f.Id]; ok {
				filtered = append(filtered, f)
			}
		}
		models = filtered
	}

	resp = &pb.ApiGetFactorysResp{
		Factorys: models,
	}
	return
}
