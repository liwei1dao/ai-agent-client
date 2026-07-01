package doubao

import (
	"context"
	"yunyan/lego/sys/log"
	"io"
	"time"

	"github.com/volcengine/volcengine-go-sdk/service/arkruntime"
	"github.com/volcengine/volcengine-go-sdk/service/arkruntime/model"
	"github.com/volcengine/volcengine-go-sdk/service/arkruntime/utils"
	"github.com/volcengine/volcengine-go-sdk/volcengine"
)

func newSys(options Options) (sys *DouBao, err error) {
	sys = &DouBao{
		options: options,
		client: arkruntime.NewClientWithApiKey(
			options.Apikey, //ARK_API_KEY 需要替换为您在平台创建的 API Key
			arkruntime.WithBaseUrl("https://ark.cn-beijing.volces.com/api/v3"),
			arkruntime.WithRegion("cn-beijing"),
		),
	}
	return
}

type DouBao struct {
	options Options
	client  *arkruntime.Client
}

func (this *DouBao) Chat(ctx context.Context, msgs []Message) (result *ChatResponseChoice, err error) {
	var (
		messages []*model.ChatCompletionMessage = make([]*model.ChatCompletionMessage, len(msgs))
		req      model.ChatRequest
		resp     model.ChatCompletionResponse
	)
	stime := time.Now()
	for i, v := range msgs {
		messages[i] = &model.ChatCompletionMessage{
			Role: v.Role,
			Content: &model.ChatCompletionMessageContent{
				StringValue: volcengine.String(v.Content),
			},
		}
	}
	req = model.CreateChatCompletionRequest{
		Model:    this.options.Model, //bot-20250328144214-rrln6 为您当前的智能体的ID，注意此处与Chat API存在差异。差异对比详见 SDK使用指南
		Messages: messages,
	}

	resp, err = this.client.CreateChatCompletion(ctx, req)
	if err != nil {
		this.options.Log.Errorf("standard chat error: %v\n", err)
		return
	}
	this.options.Log.Debug("[统计]",
		log.Field{Key: "t", Value: time.Since(stime).Milliseconds()},
		log.Field{Key: "m", Value: "Chat"},
		log.Field{Key: "req", Value: msgs},
		log.Field{Key: "resp", Value: resp},
	)
	// fmt.Println(resp)
	result = &ChatResponseChoice{
		Role:    "ai",
		Content: *resp.Choices[0].Message.Content.StringValue,
	}
	// fmt.Println(*resp.Choices[0].Message.Content.StringValue)
	// if resp.References != nil {
	// 	for _, ref := range resp.References {
	// 		fmt.Printf("reference url: %s\n", ref.Url)
	// 	}
	// }
	return
}

func (this *DouBao) ChatForSteams(ctx context.Context, msgs []Message, choiceChan chan *ChatResponseChoice) (err error) {
	var (
		messages []*model.ChatCompletionMessage = make([]*model.ChatCompletionMessage, len(msgs))
		req      model.CreateChatCompletionRequest
		recv     model.ChatCompletionStreamResponse
		stream   *utils.ChatCompletionStreamReader
	)
	stime := time.Now()
	for i, v := range msgs {
		messages[i] = &model.ChatCompletionMessage{
			Role: v.Role,
			Content: &model.ChatCompletionMessageContent{
				StringValue: volcengine.String(v.Content),
			},
		}
	}
	req = model.CreateChatCompletionRequest{
		Model:    this.options.Model, //bot-20250328144214-rrln6 为您当前的智能体的ID，注意此处与Chat API存在差异。差异对比详见 SDK使用指南
		Messages: messages,
	}
	stream, err = this.client.CreateChatCompletionStream(ctx, req)
	if err != nil {
		this.options.Log.Errorf("stream chat error: %v\n", err)
		return
	}

	defer stream.Close()
	defer close(choiceChan)
	for {
		recv, err = stream.Recv()
		if err == io.EOF {
			err = nil
			return
		}
		if err != nil {
			this.options.Log.Errorf("Stream chat error: %v\n", err)
			return
		}
		this.options.Log.Debug("[统计]",
			log.Field{Key: "t", Value: time.Since(stime).Milliseconds()},
			log.Field{Key: "m", Value: "Chat"},
			log.Field{Key: "req", Value: msgs},
		)
		if len(recv.Choices) > 0 {
			choiceChan <- &ChatResponseChoice{
				Role:    "ai",
				Content: recv.Choices[0].Delta.Content,
			}
		}
	}
}
