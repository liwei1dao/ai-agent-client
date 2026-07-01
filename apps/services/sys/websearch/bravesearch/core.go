package bravesearch

import (
	"context"

	bsearch "github.com/cnosuke/go-brave-search"
)

type (
	ISys interface {
		Search(ctx context.Context, query string, count, offset int) (results *bsearch.WebSearchResponse, err error)
		News(ctx context.Context, query string) (results *bsearch.WebSearchResponse, err error)
	}
)

var defsys ISys

func OnInit(config map[string]interface{}, option ...Option) (err error) {
	defsys, err = newSys(newOptions(config, option...))
	return
}

func NewSys(option ...Option) (sys ISys, err error) {
	sys, err = newSys(newOptionsByOption(option...))
	return
}

func Search(ctx context.Context, query string, count, offset int) (results *bsearch.WebSearchResponse, err error) {
	return defsys.Search(ctx, query, count, offset)
}

func News(ctx context.Context, query string) (results *bsearch.WebSearchResponse, err error) {
	return defsys.News(ctx, query)
}
