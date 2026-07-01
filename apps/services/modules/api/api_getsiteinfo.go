package api

import (
	"yunyan/comm"
	"yunyan/pb"
)

// 获取站点信息（公开接口，前端用于显示站点名称）
func (this *apiComp) GetSiteInfo(session comm.IUserSession, req *pb.ApiGetSiteInfoReq) (resp *pb.ApiGetSiteInfoResp, errdata *pb.ErrorData) {
	resp = &pb.ApiGetSiteInfoResp{
		Sitename:     this.options.SiteName,
		CurrencyType: this.options.CurrencyType,
	}
	return
}
