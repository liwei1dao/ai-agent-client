package api

import (
	"strconv"
	"strings"

	"yunyan/comm"
	"yunyan/pb"
)

// accountScope 描述当前登录账号在业务层的可见范围。
//
//	Unlimited=true 时（超管/管理员/未登录异常回退）表示不受工厂/产品限制。
//	Unlimited=false 时 FactoryIDs / ProductIDs 为白名单，空切片表示"看不到任何记录"。
//
// 运营(Operator) 与代理(Agent) 视作同一层，均需按白名单过滤。
type accountScope struct {
	Identity   pb.Identity
	Unlimited  bool
	FactoryIDs []uint32
	ProductIDs []uint32
}

// getSessionScope 读取 session 身份并回表查出该账号的工厂/产品白名单。
// 查不到账号时回退为"不受限"以避免误伤（权限拦截器已保证只有合法账号能到业务层）。
func (this *apiComp) getSessionScope(session comm.IUserSession) accountScope {
	identity := pb.Identity(session.GetMateToInt32("identity"))
	scope := accountScope{Identity: identity}
	if identity == pb.Identity_Admin || identity == pb.Identity_Manager {
		scope.Unlimited = true
		return scope
	}
	account := session.GetMateToString(comm.SessionMeta_UserId)
	if account == "" {
		scope.Unlimited = true
		return scope
	}
	user, err := this.module.model.findforaccount(account)
	if err != nil || user == nil {
		scope.Unlimited = true
		return scope
	}
	scope.FactoryIDs = parseUint32List(user.Factoryids)
	scope.ProductIDs = parseUint32List(user.Productids)
	return scope
}

func parseUint32List(s string) []uint32 {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil
	}
	parts := strings.Split(s, ",")
	out := make([]uint32, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p == "" {
			continue
		}
		n, err := strconv.ParseUint(p, 10, 32)
		if err != nil {
			continue
		}
		out = append(out, uint32(n))
	}
	return out
}

// visibleFactoryIDs 返回账号在工厂维度可见的工厂ID集合（已合并产品所属工厂）。
// 当 Unlimited=true 返回 nil 表示全部可见。
// 返回空切片（非 nil）表示"无任何可见工厂"。
func visibleFactoryIDs(scope accountScope, allProducts []*pb.DBProduct) []uint32 {
	if scope.Unlimited {
		return nil
	}
	set := make(map[uint32]struct{}, len(scope.FactoryIDs)+len(scope.ProductIDs))
	for _, id := range scope.FactoryIDs {
		set[id] = struct{}{}
	}
	if len(scope.ProductIDs) > 0 {
		pset := make(map[uint32]struct{}, len(scope.ProductIDs))
		for _, id := range scope.ProductIDs {
			pset[id] = struct{}{}
		}
		for _, p := range allProducts {
			if _, ok := pset[p.Id]; ok {
				set[p.Factoryid] = struct{}{}
			}
		}
	}
	out := make([]uint32, 0, len(set))
	for id := range set {
		out = append(out, id)
	}
	return out
}

// visibleProductIDs 返回账号可见的产品ID集合。
// 当 Unlimited=true 返回 nil 表示全部可见。
// 语义：
//   - 若显式配置了 ProductIDs，则严格按 ProductIDs 返回（精确白名单），
//     不再通过 FactoryIDs 反向把同厂的其它产品扩展进来；
//   - 仅当 ProductIDs 为空、且 FactoryIDs 非空时，按工厂展开其名下所有产品。
func visibleProductIDs(scope accountScope, allProducts []*pb.DBProduct) []uint32 {
	if scope.Unlimited {
		return nil
	}
	if len(scope.ProductIDs) > 0 {
		out := make([]uint32, len(scope.ProductIDs))
		copy(out, scope.ProductIDs)
		return out
	}
	if len(scope.FactoryIDs) == 0 {
		return []uint32{}
	}
	fset := make(map[uint32]struct{}, len(scope.FactoryIDs))
	for _, id := range scope.FactoryIDs {
		fset[id] = struct{}{}
	}
	set := make(map[uint32]struct{})
	for _, p := range allProducts {
		if _, ok := fset[p.Factoryid]; ok {
			set[p.Id] = struct{}{}
		}
	}
	out := make([]uint32, 0, len(set))
	for id := range set {
		out = append(out, id)
	}
	return out
}
