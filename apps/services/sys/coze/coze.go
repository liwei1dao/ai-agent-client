package coze

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"time"

	"github.com/coze-dev/coze-go"
)

func newSys(options Options) (sys *Coze, err error) {
	sys = &Coze{
		options: options,
	}
	// sys.Init()
	authCli := coze.NewTokenAuth(options.Token)
	sys.api = coze.NewCozeAPI(authCli, coze.WithBaseURL(coze.CnBaseURL))
	return
}

type Coze struct {
	options Options
	api     coze.CozeAPI
}

func (this *Coze) Init() {
	// Get an access_token through personal access token or oauth.
	// token := os.Getenv("COZE_API_TOKEN")
	authCli := coze.NewTokenAuth(this.options.Token)

	// 1. Initialize with default configuration
	cozeCli1 := coze.NewCozeAPI(authCli)
	fmt.Println("client 1:", cozeCli1)

	// 2. Initialize with custom base URL
	// cozeAPIBase := os.Getenv("COZE_API_BASE")
	cozeCli2 := coze.NewCozeAPI(authCli, coze.WithBaseURL(coze.ComBaseURL))
	fmt.Println("client 2:", cozeCli2)

	// 3. Initialize with custom HTTP client
	customClient := &http.Client{
		Timeout: 30 * time.Second,
		Transport: &http.Transport{
			MaxIdleConns:        100,
			MaxIdleConnsPerHost: 100,
			IdleConnTimeout:     90 * time.Second,
		},
	}
	cozeCli3 := coze.NewCozeAPI(authCli,
		coze.WithBaseURL(coze.ComBaseURL),
		coze.WithHttpClient(customClient),
	)
	fmt.Println("client 3:", cozeCli3)
}

func (this *Coze) ChatForSteams(ctx context.Context, uid string, customVariables map[string]string, messages []Message, choiceChan chan *ChatResponseChoice) (err error) {
	var (
		msgs []*coze.Message = make([]*coze.Message, len(messages))
		resp coze.Stream[coze.ChatEvent]
	)

	for i, v := range messages {
		msgs[i] = &coze.Message{
			Role:    coze.MessageRoleUser,
			Content: v.Content,
		}
	}
	req := &coze.CreateChatsReq{
		BotID:           this.options.BotID,
		UserID:          uid,
		Messages:        msgs,
		CustomVariables: customVariables,
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	defer close(choiceChan)
	if resp, err = this.api.Chat.Stream(ctx, req); err != nil {
		this.options.Log.Errorln(err)
		return
	}
	defer resp.Close()
	for {
		event, err := resp.Recv()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			this.options.Log.Errorln(err)
			break
		}
		// fmt.Printf("结果:Event: %s Message:%+v \n", event.Event, event.Message)
		if event.Event == coze.ChatEventConversationMessageDelta {
			choiceChan <- &ChatResponseChoice{
				Role:    "ai",
				Content: event.Message.Content,
			}
		} else if event.Event == coze.ChatEventConversationMessageCompleted {
			if event.Message.Type == coze.MessageTypeToolResponse {
				// fmt.Printf("结果:Event: %s Message:%+v \n\n\n", event.Event, event.Message)
				card := CardContent{}
				if err = json.Unmarshal([]byte(event.Message.Content), &card); err != nil {
					this.options.Log.Errorln(err)
				} else {
					data := CardContentData{}
					if card.Data != "" {
						if err = json.Unmarshal([]byte(card.Data), &data); err != nil {
							fmt.Println(card.Data)
							this.options.Log.Errorln(card.Data, err)
						} else {
							if len(data.Variables) > 0 {
								for _, v := range data.Variables {
									choiceChan <- &ChatResponseChoice{
										Role: "card",
										Meta: map[string]interface{}{
											v.Name: v.DefaultValue,
										},
									}
								}

							}
						}
					}
				}
			}
		}
	}
	return
}
