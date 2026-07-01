package bravesearch_test

import (
	"context"
	"fmt"
	"log"
	"os"
	"testing"
	"yunyan/sys/websearch/bravesearch"

	bsearch "github.com/cnosuke/go-brave-search"
)

func Test_Handle(t *testing.T) {
	apiKey := os.Getenv("BRAVE_SEARCH_API_KEY")
	if apiKey == "" {
		t.Skip("BRAVE_SEARCH_API_KEY env not set")
	}
	// Create a new client with your API key
	client, err := bsearch.NewClient(apiKey)
	if err != nil {
		log.Fatalf("Failed to create client: %v", err)
	}

	// Create a context
	ctx := context.Background()

	// Perform a web search
	results, err := client.WebSearch(ctx, "茅台股价", nil)
	if err != nil {
		log.Fatalf("Search failed: %v", err)
	}

	// Print the results
	fmt.Printf("Search results for 'brave search':\n")
	for i, result := range results.Web.Results {
		fmt.Printf("%d. %s\n", i+1, result.Title)
		fmt.Printf("   URL: %s\n", result.URL)
		fmt.Printf("   Description: %s\n\n", result.Description)
	}
}

func Test_Sys(t *testing.T) {
	apiKey := os.Getenv("BRAVE_SEARCH_API_KEY")
	if apiKey == "" {
		t.Skip("BRAVE_SEARCH_API_KEY env not set")
	}
	if err := bravesearch.OnInit(nil,
		bravesearch.SetApiKey(apiKey),
		bravesearch.SetCountry("CN"),             // 中国
		bravesearch.SetSearchLanguage("zh-hans"), // 中文（注意：使用 zh，而不是 cn）
		bravesearch.SetUILanguage("zh-CN"),       // 中文（中国地区）
	); err != nil {
		return
	} else {
		results, err := bravesearch.Search(context.TODO(), "衡阳市和深圳市面积对比", 5, 0)
		fmt.Println(results, err)
	}
}
