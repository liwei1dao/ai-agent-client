package deepseek

type (
	ISys interface {
		Chat(msgs []Message) (result []string, err error)
	}
	//消息
	Message struct {
		//发起消息的角色
		//Possible values: [system,user,assistant,tool];
		Role string `json:"role"`
		//消息的内容
		Content string `json:"content"`
		//是否访问网络
		Web bool `json:"web"`
		//可以选填的参与者的名称，为模型提供信息以区分相同角色的参与者。
		Name string `json:"name"`
		//(Beta) 设置此参数为 true，来强制模型在其回答中以此 assistant 消息中提供的前缀内容开始。
		//您必须设置 base_url="https://api.deepseek.com/beta" 来使用此功能
		Prefix bool `json:"prefix"`
		//(Beta) 用于 deepseek-reasoner 模型在对话前缀续写功能下，作为最后一条 assistant 思维链内容的输入。使用此功能时，prefix 参数必须设置为 true。
		ReasoningContent string `json:"reasoning_content"`
		//此消息所响应的 tool call 的 ID。
		ToolCallId string `json:"tool_call_id"`
	}
	//回应控制
	ResponesFormat struct {
		Type string `json:"type"`
	}
	//流式参数
	StreaOptions struct {
		//如果设置为 true，在流式消息最后的 data: [DONE] 之前将会传输一个额外的块。此块上的 usage 字段显示整个请求的 token 使用统计信息，而 choices 字段将始终是一个空数组。所有其他块也将包含一个 usage 字段，但其值为 null。
		IncludeUsage bool `json:"include_usage"`
	}
	//工具
	Tool struct {
		Type     string   `json:"type"`     //工具名称
		Function Function `json:"function"` //工具名称
	}
	//工具
	Function struct {
		Name        string     `json:"name"`        //方法名称
		Description string     `json:"description"` //方法描述
		Parameters  Parameters `json:"parameters"`  //参数列表
	}
	//方法调用 参数列表
	Parameters struct {
		Type       string               `json:"type"`       //传参勒烯
		Properties map[string]Propertie `json:"properties"` //参数列表
		Required   []string             `json:"required"`   //必传参数列表
	}
	//参数
	Propertie struct {
		Type        string `json:"type"`        //参数类型
		Description string `json:"description"` //参数描述
	}
	ChatRequest struct {
		//对话的消息列表。
		Messages []Message `json:"messages"`
		//Possible values: [deepseek-chat, deepseek-reasoner];
		//使用的模型的 ID。您可以使用 deepseek-chat。
		Model string `json:"model"`
		//Possible values: >= -2 and <= 2;
		//Default value: 0;
		//介于 -2.0 和 2.0 之间的数字。如果该值为正，那么新 token 会根据其在已有文本中的出现频率受到相应的惩罚，降低模型重复相同内容的可能性。
		FrequencyPenalty string `json:"frequency_penalty"`
		//Possible values: > 1;
		//介于 1 到 8192 间的整数，限制一次请求中模型生成 completion 的最大 token 数。输入 token 和输出 token 的总长度受模型的上下文长度的限制。
		//如未指定 max_tokens参数，默认使用 4096。
		MaxTokens int `json:"max_tokens"`
		//Possible values: >= -2 and <= 2
		//Default value: 0
		//介于 -2.0 和 2.0 之间的数字。如果该值为正，那么新 token 会根据其是否已在已有文本中出现受到相应的惩罚，从而增加模型谈论新主题的可能性。
		PresencePenalty int `json:"presence_penalty"`
		//一个 object，指定模型必须输出的格式。设置为 { "type": "json_object" } 以启用 JSON 模式，该模式保证模型生成的消息是有效的 JSON。
		//注意: 使用 JSON 模式时，你还必须通过系统或用户消息指示模型生成 JSON。否则，模型可能会生成不断的空白字符，直到生成达到令牌限制，从而导致请求长时间运行并显得“卡住”。此外，如果 finish_reason="length"，这表示生成超过了 max_tokens 或对话超过了最大上下文长度，消息内容可能会被部分截断
		ResponesFormat ResponesFormat `json:"response_format"`
		//一个 string 或最多包含 16 个 string 的 list，在遇到这些词时，API 将停止生成更多的 token。
		Stop []string `json:"stop"`
		//如果设置为 True，将会以 SSE（server-sent events）的形式以流式发送消息增量。消息流以
		Stream bool `json:"stream"`
		//流式输出相关选项。只有在 stream 参数为 true 时，才可设置此参数
		StreaOptions *StreaOptions `json:"stream_options"`
		//Possible values: <= 2
		//Default value: 1
		//采样温度，介于 0 和 2 之间。更高的值，如 0.8，会使输出更随机，而更低的值，如 0.2，会使其更加集中和确定。 我们通常建议可以更改这个值或者更改 top_p，但不建议同时对两者进行修改。
		Temperature int `json:"temperature"`
		//Possible values: <= 1
		//Default value: 1
		//作为调节采样温度的替代方案，模型会考虑前 top_p 概率的 token 的结果。所以 0.1 就意味着只有包括在最高 10% 概率中的 token 会被考虑。 我们通常建议修改这个值或者更改 temperature，但不建议同时对两者进行修改
		TopP int `json:"top_p"`
		//模型可能会调用的 tool 的列表。目前，仅支持 function 作为工具。使用此参数来提供以 JSON 作为输入参数的 function 列表。最多支持 128 个 function。
		Tools []Tool
	}

	ChatResponse struct {
		// 根据实际的API响应定义结构体字段
		// 例如：
		Choices []struct {
			Message Message `json:"message"`
		} `json:"choices"`
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

func Chat(msgs []Message) (result []string, err error) {
	return defsys.Chat(msgs)
}
