package openai

import (
	"context"
	"fmt"
	"io"
	"strings"

	"github.com/sashabaranov/go-openai"
)

func newSys(options Options) (sys *Openai, err error) {
	sys = &Openai{
		options: options,
	}
	// 初始化客户端
	config := openai.DefaultConfig(options.Token)
	config.BaseURL = options.BaseURL
	sys.client = openai.NewClientWithConfig(config)
	return
}

type Openai struct {
	options   Options
	client    *openai.Client
	toolinfos []openai.Tool //工具 JSON Schema
	tools     []ITool       //工具对应的执行函数
}

// 注册工具
func (this *Openai) RegisterTools(tool ITool) {
	this.toolinfos = append(this.toolinfos, tool.GetToolInfo())
	this.tools = append(this.tools, tool)

}

func (this *Openai) Chat(ctx context.Context, msgs []ChatReq) (resp *ChatResponse, err error) {
	var (
		count       int = 0
		messages    []openai.ChatCompletionMessage
		message     openai.ChatCompletionMessage
		meta        map[string]any = make(map[string]any)
		toolresult  any
		toolcontext string
	)
	messages = make([]openai.ChatCompletionMessage, len(msgs))
	for i, v := range msgs {
		messages[i] = openai.ChatCompletionMessage{
			Role:    v.Role,
			Content: v.Content,
		}
	}
	// 第一次请求（获取工具调用）
	message, err = this.sendMessage(ctx, messages, this.toolinfos)
	if err != nil {
		return
	}

	// 处理工具调用
	for len(message.ToolCalls) > 0 && count < this.options.Maxfunccall { //循环执行ai代码
		count++
		toolCall := message.ToolCalls[0]
		messages = append(messages, message)

		if toolresult, toolcontext, err = this.FunctionCall(toolCall); err != nil {
			return
		}
		meta[toolCall.Function.Name] = toolresult
		// content, _ := json.Marshal(toolresult)
		// 添加工具响应
		messages = append(messages, openai.ChatCompletionMessage{
			Role:       "tool", // 注意：go-openai库暂未预定义该角色
			Content:    toolcontext,
			ToolCallID: toolCall.ID,
		})
		// 第二次请求（获取最终回答）
		message, err = this.sendMessage(ctx, messages, nil) // 不再需要传递工具
		if err != nil {
			return
		}
	}
	resp = &ChatResponse{
		Role:    message.Role,
		Content: message.Content,
		Meta:    meta,
	}
	return
}

func (this *Openai) ChatForSteams(ctx context.Context, msgs []ChatReq, choiceChan chan *ChatResponseChoice) (err error) {
	defer close(choiceChan) //关闭输出流
	var (
		count       = 0
		messages    []openai.ChatCompletionMessage
		message     openai.ChatCompletionMessage
		meta        map[string]any = make(map[string]any)
		toolresult  any
		toolcontext string
	)
	messages = make([]openai.ChatCompletionMessage, len(msgs))
	for i, v := range msgs {
		messages[i] = openai.ChatCompletionMessage{
			Role:    v.Role,
			Content: v.Content,
		}
	}
	// 第一次请求（获取工具调用）
	message, err = this.sendMessagForSteam(ctx, messages, this.toolinfos, choiceChan)
	if err != nil {
		this.options.Log.Errorln(err)
		return
	}
	// 处理工具调用
	for len(message.ToolCalls) > 0 && count < this.options.Maxfunccall { //循环执行ai代码
		toolCall := message.ToolCalls[0]
		messages = append(messages, message)

		if toolresult, toolcontext, err = this.FunctionCall(toolCall); err != nil {
			this.options.Log.Errorln(err)
			return
		}
		meta[toolCall.Function.Name] = toolresult
		// content, _ := json.Marshal(toolresult)
		// 添加工具响应
		messages = append(messages, openai.ChatCompletionMessage{
			Role:       "tool", // 注意：go-openai库暂未预定义该角色
			Content:    toolcontext,
			ToolCallID: toolCall.ID,
		})
		choiceChan <- &ChatResponseChoice{
			Role: "tool",
			Meta: meta,
		}
		// 第二次请求（获取最终回答）
		message, err = this.sendMessagForSteam(ctx, messages, this.toolinfos, choiceChan) // 不再需要传递工具
		if err != nil {
			this.options.Log.Errorln(err)
			return
		}
	}
	return
}
func (this *Openai) FunctionCall(call openai.ToolCall) (result any, content string, err error) {
	var (
		tool ITool
	)
	for i, v := range this.toolinfos {
		if call.Function.Name == v.Function.Name { //确定工具
			tool = this.tools[i]
			break
		}
	}
	if tool != nil {
		result, content, err = tool.Execute([]byte(call.Function.Arguments))
	}
	return
}

func (this *Openai) CreateChatCompletion(ctx context.Context, request openai.ChatCompletionRequest) (response openai.ChatCompletionResponse, err error) {
	response, err = this.client.CreateChatCompletion(ctx, request)
	return
}
func (this *Openai) CreateChatCompletionStream(ctx context.Context, request openai.ChatCompletionRequest) (stream *openai.ChatCompletionStream, err error) {
	stream, err = this.client.CreateChatCompletionStream(ctx, request)
	return
}
func (this *Openai) sendMessage(ctx context.Context, messages []openai.ChatCompletionMessage, tools []openai.Tool) (openai.ChatCompletionMessage, error) {
	req := openai.ChatCompletionRequest{
		Model:    this.options.Model,
		Messages: messages,
		Tools:    tools, // 工具参数在首次请求时传递
	}
	resp, err := this.client.CreateChatCompletion(ctx, req)
	if err != nil {
		return openai.ChatCompletionMessage{}, err
	}
	if len(resp.Choices) == 0 {
		return openai.ChatCompletionMessage{}, fmt.Errorf("empty response")
	}
	return resp.Choices[0].Message, nil
}

func (this *Openai) sendMessagForSteam(ctx context.Context, messages []openai.ChatCompletionMessage, tools []openai.Tool, choiceChan chan *ChatResponseChoice) (openai.ChatCompletionMessage, error) {

	// 创建流式请求
	req := openai.ChatCompletionRequest{
		Model:    this.options.Model,
		Messages: messages,
		Tools:    tools,
		Stream:   true, // 启用流式模式
	}

	// 创建上下文（可添加超时控制）
	stream, err := this.client.CreateChatCompletionStream(ctx, req)
	if err != nil {
		return openai.ChatCompletionMessage{}, err
	}
	defer stream.Close()

	// 初始化结果收集器
	var fullResponse strings.Builder
	var toolCalls []openai.ToolCall

	for {
		response, err := stream.Recv()
		if err == io.EOF {
			break
		}
		if err != nil {
			return openai.ChatCompletionMessage{}, err
		}

		// 处理每个 chunk
		for _, choice := range response.Choices {
			// 收集工具调用信息
			if len(choice.Delta.ToolCalls) > 0 {
				toolCalls = processToolCallDelta(toolCalls, choice.Delta.ToolCalls)
			}

			// 收集内容增量
			if choice.Delta.Content != "" {
				// fmt.Print(choice.Delta.Content) // 实时输出
				fullResponse.WriteString(choice.Delta.Content)
				choiceChan <- &ChatResponseChoice{
					Role:    choice.Delta.Role,
					Content: choice.Delta.Content,
				}
			}
		}
	}

	// 构建最终消息
	return openai.ChatCompletionMessage{
		Role:      openai.ChatMessageRoleAssistant,
		Content:   fullResponse.String(),
		ToolCalls: toolCalls,
	}, nil
}

// 处理工具调用的增量更新
func processToolCallDelta(existing []openai.ToolCall, deltas []openai.ToolCall) []openai.ToolCall {
	for _, delta := range deltas {
		if *delta.Index >= len(existing) {
			// 新增工具调用
			existing = append(existing, openai.ToolCall{
				ID:   delta.ID,
				Type: delta.Type,
				Function: openai.FunctionCall{
					Name:      delta.Function.Name,
					Arguments: delta.Function.Arguments,
				},
			})
		} else {
			// 更新现有工具调用参数
			existing[*delta.Index].Function.Arguments += delta.Function.Arguments
		}
	}
	return existing
}
