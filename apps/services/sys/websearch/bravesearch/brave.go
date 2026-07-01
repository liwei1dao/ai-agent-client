package bravesearch

import (
	"context"

	bsearch "github.com/cnosuke/go-brave-search"
)

func newSys(options Options) (sys *BraveSearch, err error) {
	sys = &BraveSearch{
		options: options,
	}
	sys.client, err = bsearch.NewClient(options.ApiKey,
		bsearch.WithTimeout(30),                                   // Request timeout in seconds
		bsearch.WithRetries(3),                                    // Number of retries on transient errors
		bsearch.WithUserAgent("MyApp/1.0"),                        // Custom User-Agent
		bsearch.WithDefaultCountry(options.Country),               // Default country for searches
		bsearch.WithDefaultSearchLanguage(options.SearchLanguage), // Default search language
		bsearch.WithDefaultUILanguage(options.UILanguage),         // Default UI language
	)
	if err != nil {
		return
	}
	return
}

type BraveSearch struct {
	options Options
	client  *bsearch.Client
}

// 搜索网页信息
func (this *BraveSearch) Search(ctx context.Context, query string, count, offset int) (results *bsearch.WebSearchResponse, err error) {
	results, err = this.client.WebSearch(ctx, query, &bsearch.WebSearchParams{
		Count:           count,
		Offset:          offset,
		SafeSearch:      "moderate",
		Freshness:       bsearch.FreshnessWeek,
		TextDecorations: true,
		Summary:         true,
	})
	return
}

// 新闻搜索
func (this *BraveSearch) News(ctx context.Context, query string) (results *bsearch.WebSearchResponse, err error) {
	results, err = this.client.WebSearchNews(ctx, query)
	return
}
