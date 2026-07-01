package doubao_test

import (
	"context"
	"fmt"
	"io"
	"os"
	"testing"
	"yunyan/sys/doubao"

	"github.com/volcengine/volcengine-go-sdk/service/arkruntime"
	"github.com/volcengine/volcengine-go-sdk/service/arkruntime/model"
	"github.com/volcengine/volcengine-go-sdk/volcengine"
)

func Test_Sys_Chat(t *testing.T) {
	apiKey := os.Getenv("DOUBAO_API_KEY")
	if apiKey == "" {
		t.Skip("DOUBAO_API_KEY env not set")
	}
	if sys, err := doubao.NewSys(
		doubao.SetApikey(apiKey),
		doubao.SetModel("doubao-1-5-pro-32k-250115"),
	); err != nil {
		fmt.Printf("Sys Init err:%v", err)
	} else {
		// xal, _ := axml.NewSys()
		result, err := sys.Chat(context.Background(), []doubao.Message{{
			Role:    "user",
			Content: "茅台的股价",
		}})
		fmt.Printf(" result:%v err:%v", result, err)
	}
}

func Test_Sys_SDK(t *testing.T) {
	apiKey := os.Getenv("DOUBAO_API_KEY")
	botID := os.Getenv("DOUBAO_BOT_ID")
	if apiKey == "" || botID == "" {
		t.Skip("DOUBAO_API_KEY/DOUBAO_BOT_ID env not set")
	}
	client := arkruntime.NewClientWithApiKey(
		apiKey, //ARK_API_KEY 需要替换为您在平台创建的 API Key
		arkruntime.WithBaseUrl("https://ark.cn-beijing.volces.com/api/v3"),
		arkruntime.WithRegion("cn-beijing"),
	)

	ctx := context.Background()

	fmt.Println("----- standard request -----")
	req := model.BotChatCompletionRequest{
		BotId: botID, //bot id 为您当前的智能体的ID，注意此处与Chat API存在差异。差异对比详见 SDK使用指南
		Messages: []*model.ChatCompletionMessage{
			{
				Role: model.ChatMessageRoleSystem,
				Content: &model.ChatCompletionMessageContent{
					StringValue: volcengine.String("你是豆包，是由字节跳动开发的 AI 人工智能助手"),
				},
			},
			{
				Role: model.ChatMessageRoleUser,
				Content: &model.ChatCompletionMessageContent{
					StringValue: volcengine.String("武汉今日天气如何？"),
				},
			},
		},
	}

	resp, err := client.CreateBotChatCompletion(ctx, req)
	if err != nil {
		fmt.Printf("standard chat error: %v\n", err)
		return
	}
	fmt.Println(*resp.Choices[0].Message.Content.StringValue)
	if resp.References != nil {
		for _, ref := range resp.References {
			fmt.Printf("reference url: %s\n", ref.Url)
		}
	}

	fmt.Println("----- multiple rounds request -----")
	req = model.BotChatCompletionRequest{
		BotId: botID, //bot id 为您当前的智能体的ID，注意此处与Chat API存在差异。差异对比详见 SDK使用指南
		Messages: []*model.ChatCompletionMessage{ //通过会话传递历史信息，模型会参考上下文消息
			{
				Role: model.ChatMessageRoleSystem,
				Content: &model.ChatCompletionMessageContent{
					StringValue: volcengine.String("你是豆包，字节跳动开发的 AI 人工智能助手"),
				},
			},
			{
				Role: model.ChatMessageRoleUser,
				Content: &model.ChatCompletionMessageContent{
					StringValue: volcengine.String("茅台今日股价如何？"),
				},
			},
		},
	}

	resp, err = client.CreateBotChatCompletion(ctx, req)
	if err != nil {
		fmt.Printf("multiple chat error: %v\n", err)
		return
	}
	fmt.Println(*resp.Choices[0].Message.Content.StringValue)
	if resp.References != nil {
		for _, ref := range resp.References {
			fmt.Printf("reference url: %s\n", ref.Url)
		}
	}

	fmt.Println("----- streaming request -----")
	req = model.BotChatCompletionRequest{
		BotId: botID, //bot id 为您当前的智能体的ID，注意此处与Chat API存在差异。差异对比详见 SDK使用指南
		Messages: []*model.ChatCompletionMessage{
			{
				Role: model.ChatMessageRoleSystem,
				Content: &model.ChatCompletionMessageContent{
					StringValue: volcengine.String("你是豆包，是由字节跳动开发的 AI 人工智能助手"),
				},
			},
			{
				Role: model.ChatMessageRoleUser,
				Content: &model.ChatCompletionMessageContent{
					StringValue: volcengine.String("深圳今日天气如何？"),
				},
			},
		},
	}
	stream, err := client.CreateBotChatCompletionStream(ctx, req)
	if err != nil {
		fmt.Printf("stream chat error: %v\n", err)
		return
	}
	defer stream.Close()

	for {
		recv, err := stream.Recv()
		if err == io.EOF {
			return
		}
		if err != nil {
			fmt.Printf("Stream chat error: %v\n", err)
			return
		}

		if len(recv.Choices) > 0 {
			fmt.Print(recv.Choices[0].Delta.Content)
			if recv.References != nil {
				for _, ref := range recv.References {
					fmt.Printf("reference url: %s\n", ref.Url)
				}
			}
		}
	}
}
