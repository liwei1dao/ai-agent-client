package deepseek

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"sync"
)

func newSys(options Options) (sys *Deepseek, err error) {
	sys = &Deepseek{
		options: options,
		pool: sync.Pool{
			New: func() interface{} {
				return &http.Client{}
			},
		}}

	return
}

type Deepseek struct {
	options Options
	pool    sync.Pool
}

func (this *Deepseek) Chat(msgs []Message) (result []string, err error) {
	var (
		jsonData []byte
		body     []byte
		resp     *http.Response
	)

	url := "https://api.deepseek.com/v1/chat/completions"
	chatRequest := ChatRequest{
		Model:    "deepseek-chat",
		Messages: msgs,
		Stream:   false,
	}

	jsonData, err = json.Marshal(chatRequest)
	if err != nil {
		fmt.Println("Error marshalling JSON:", err)
		return
	}

	req, err := http.NewRequest("POST", url, bytes.NewBuffer(jsonData))
	if err != nil {
		fmt.Println("Error creating request:", err)
		return
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+this.options.Appkey)

	client := this.pool.Get().(*http.Client)
	defer this.pool.Put(client)
	resp, err = client.Do(req)
	if err != nil {
		this.options.Log.Errorln("Error making request:", err)
		return
	}
	defer resp.Body.Close()

	body, err = io.ReadAll(resp.Body)
	if err != nil {
		fmt.Println("Error reading response body:", err)
		return
	}

	var chatResponse ChatResponse
	err = json.Unmarshal(body, &chatResponse)
	if err != nil {
		fmt.Println("Error unmarshalling response:", err)
		return
	}
	result = make([]string, len(chatResponse.Choices))
	// 输出响应结果
	for _, choice := range chatResponse.Choices {
		// fmt.Println("Response:", choice.Message.Content)
		result = append(result, choice.Message.Content)
	}
	return
}
