package openai_test

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"testing"
	"yunyan/sys/juhe"
	"yunyan/sys/openai"
	tavily "yunyan/sys/websearch/tavilysearch"

	ai "github.com/sashabaranov/go-openai"
)

type Tool_Search_Req struct {
	Query string `json:"query"`
}
type search struct{}

func (this *search) GetToolInfo() ai.Tool {
	// 定义工具列表
	tool := ai.Tool{
		Type: "function",
		Function: &ai.FunctionDefinition{
			Name:        "search",
			Description: "通过Tavily搜索引擎获取实时网络信息,例如查询股票id,实时新闻等",
			Parameters: openai.Parameters{
				Type: "object",
				Properties: map[string]openai.Property{
					"query": {
						Type:        "string",
						Description: "搜索关键词",
					},
				},
				Required: []string{"query"},
			},
		},
	}
	return tool
}
func (this *search) Execute(args json.RawMessage) (data any, text string, err error) {
	var (
		req    Tool_Search_Req
		result *tavily.TavilyResponse
	)
	fmt.Println("search", string(args))
	if err := json.Unmarshal(args, &req); err != nil {
		return nil, "输入参数错误", fmt.Errorf("参数解析失败: %v", err)
	}
	if result, err = tavily.Search(context.Background(), req.Query, 10, 24); err != nil {
		return
	}
	data = result
	text = result.Results[0].Content
	return
}

type Tool_Finance_Req struct {
	Gid string `json:"gid"`
}
type finance struct{}

func (this *finance) GetToolInfo() ai.Tool {
	// 定义工具列表
	tool := ai.Tool{
		Type: "function",
		Function: &ai.FunctionDefinition{
			Name:        "finance",
			Description: "通过股票ID的可以查询当前实时股票的数据",
			Parameters: openai.Parameters{
				Type: "object",
				Properties: map[string]openai.Property{
					"gid": {
						Type:        "string",
						Description: "股票ID,需要按照 sh开头的格式,例如:sh601009",
					},
				},
				Required: []string{"gid"},
			},
		},
	}
	return tool
}
func (this *finance) Execute(args json.RawMessage) (data any, context string, err error) {
	var (
		req    Tool_Finance_Req
		result *juhe.StockResponse
	)
	fmt.Println("finance", string(args))
	if err := json.Unmarshal(args, &req); err != nil {
		return nil, "输入参数错误", fmt.Errorf("参数解析失败: %v", err)
	}
	if result, err = juhe.Financebygid(req.Gid); err != nil {
		return
	}
	data = result
	context = fmt.Sprintf("当前%s股票情况:今日开盘价:%s,昨日收盘价:%s,当前价格:%s,今日最高价:%s,今日最低价:%s,成交量:%s,成交金额:%s",
		result.FinanceResult[0].Data.Name,
		result.FinanceResult[0].Data.TodayStartPri,
		result.FinanceResult[0].Data.YestodEndPri,
		result.FinanceResult[0].Data.NowPri,
		result.FinanceResult[0].Data.TodayMax,
		result.FinanceResult[0].Data.TodayMin,
		result.FinanceResult[0].Data.TraNumber,
		result.FinanceResult[0].Data.TraAmount,
	)
	return
}

func Test_Sys_Chat(t *testing.T) {
	openaiAPIKey := os.Getenv("OPENAI_API_KEY")
	if openaiAPIKey == "" {
		t.Skip("OPENAI_API_KEY env not set")
	}
	if sys, err := openai.NewSys(
		openai.SetBaseURL("https://api.deepseek.com/v1"),
		openai.SetToken(openaiAPIKey),
		openai.SetModel("deepseek-chat"),
	); err != nil {
		fmt.Printf("Sys Init err:%v", err)
	} else {
		var resp *openai.ChatResponse
		// 初始化对话
		messages := []openai.ChatReq{
			{
				Role:    ai.ChatMessageRoleUser,
				Content: "你好呀",
			},
		}
		resp, err = sys.Chat(context.Background(), messages)
		fmt.Printf("resp:%+v err:%v", resp, err)
	}
}

func Test_Sys_ChatSteam(t *testing.T) {
	openaiAPIKey := os.Getenv("OPENAI_API_KEY")
	tavilyAPIKey := os.Getenv("TAVILY_API_KEY")
	juheAPIKey := os.Getenv("JUHE_FINANCE_API_KEY")
	if openaiAPIKey == "" || tavilyAPIKey == "" || juheAPIKey == "" {
		t.Skip("OPENAI_API_KEY / TAVILY_API_KEY / JUHE_FINANCE_API_KEY env not set")
	}
	tavily.OnInit(nil,
		tavily.SetApiKey(tavilyAPIKey),
	)
	juhe.OnInit(nil,
		juhe.SetFinance_ApiKey(juheAPIKey),
	)
	if sys, err := openai.NewSys(
		openai.SetBaseURL("https://api.deepseek.com/v1"),
		openai.SetToken(openaiAPIKey),
		openai.SetModel("deepseek-chat"),
		openai.SetMaxfunccall(5),
	); err != nil {
		fmt.Printf("Sys Init err:%v", err)
	} else {
		// 初始化对话
		messages := []openai.ChatReq{
			{
				Role:    ai.ChatMessageRoleUser,
				Content: "茅台的今日股价如何?",
			},
		}
		sys.RegisterTools(&search{})
		sys.RegisterTools(&finance{})
		choiceChan := make(chan *openai.ChatResponseChoice, 1)
		go sys.ChatForSteams(context.Background(), messages, choiceChan)
		for v := range choiceChan {
			fmt.Printf("%+v\n", v)
		}
	}
}

func Test_Sys_doubao(t *testing.T) {
	doubaoToken := os.Getenv("OPENAI_DOUBAO_TOKEN")
	if doubaoToken == "" {
		t.Skip("OPENAI_DOUBAO_TOKEN env not set")
	}
	if sys, err := openai.NewSys(
		openai.SetBaseURL("https://ark.cn-beijing.volces.com/api/v3/bots"),
		openai.SetToken(doubaoToken),
		openai.SetModel("bot-20250328144214-rrln6"),
	); err != nil {
		fmt.Printf("Sys Init err:%v", err)
	} else {
		var resp *openai.ChatResponse
		// 初始化对话
		messages := []openai.ChatReq{
			{
				Role:    ai.ChatMessageRoleUser,
				Content: "茅台今日股价？",
			},
		}
		resp, err = sys.Chat(context.Background(), messages)
		fmt.Printf("resp:%+v err:%v", resp, err)
	}
}
func Test_Sys_doubao_steam(t *testing.T) {
	doubaoToken := os.Getenv("OPENAI_DOUBAO_TOKEN")
	tavilyAPIKey := os.Getenv("TAVILY_API_KEY")
	if doubaoToken == "" || tavilyAPIKey == "" {
		t.Skip("OPENAI_DOUBAO_TOKEN / TAVILY_API_KEY env not set")
	}
	tavily.OnInit(nil,
		tavily.SetApiKey(tavilyAPIKey),
	)
	if sys, err := openai.NewSys(
		openai.SetBaseURL("https://ark.cn-beijing.volces.com/api/v3/bots"),
		openai.SetToken(doubaoToken),
		openai.SetModel("bot-20250328144214-rrln6"),
	); err != nil {
		fmt.Printf("Sys Init err:%v", err)
	} else {
		// 初始化对话
		messages := []openai.ChatReq{
			{
				Role:    ai.ChatMessageRoleUser,
				Content: "茅台的今日股价如何?",
			},
		}
		choiceChan := make(chan *openai.ChatResponseChoice, 1)
		go sys.ChatForSteams(context.Background(), messages, choiceChan)
		for v := range choiceChan {
			fmt.Printf("%+v\n", v)
		}
	}
}

func Test_Sys_oneapi_steam(t *testing.T) {
	openaiAPIKey2 := os.Getenv("OPENAI_API_KEY_2")
	juheAPIKey := os.Getenv("JUHE_FINANCE_API_KEY")
	if openaiAPIKey2 == "" || juheAPIKey == "" {
		t.Skip("OPENAI_API_KEY_2 / JUHE_FINANCE_API_KEY env not set")
	}
	// tavily.OnInit(nil,
	// 	tavily.SetApiKey(os.Getenv("TAVILY_API_KEY")),
	// )
	juhe.OnInit(nil,
		juhe.SetFinance_ApiKey(juheAPIKey),
	)
	if sys, err := openai.NewSys(
		openai.SetBaseURL("http://127.0.0.1:3000/v1"),
		openai.SetToken(openaiAPIKey2),
		openai.SetModel("gpt-3.5-turbo"),
	); err != nil {
		fmt.Printf("Sys Init err:%v", err)
	} else {
		// 初始化对话
		messages := []openai.ChatReq{
			{
				Role:    ai.ChatMessageRoleUser,
				Content: "股票代码:sh601009,今日行情咋样",
			},
		}
		choiceChan := make(chan *openai.ChatResponseChoice, 1)
		// sys.RegisterTools(&search{})
		sys.RegisterTools(&finance{})
		go sys.ChatForSteams(context.Background(), messages, choiceChan)
		for v := range choiceChan {
			fmt.Printf("%+v\n", v)
		}
	}
}
