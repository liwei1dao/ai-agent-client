package lghttp

import (
	"bytes"
	"context"
	"yunyan/lego/sys/log"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

func newSys(options Options) (sys *Fasthttp, err error) {
	sys = &Fasthttp{options: options}
	sys.client = &http.Client{
		Transport: &http.Transport{
			MaxIdleConns:        10,
			MaxIdleConnsPerHost: 10,
			IdleConnTimeout:     30 * time.Second,
		},
	}
	return
}

type Fasthttp struct {
	options Options
	client  *http.Client
}

func (this *Fasthttp) RequestForJson(ctx context.Context, method string, url string, args, result interface{}) (err error) {
	var (
		req      *http.Request
		resp     *http.Response
		reqbody  []byte
		respbody []byte
	)
	this.options.Log.Debug("RequestForJson", log.Field{Key: "method", Value: method}, log.Field{Key: "url", Value: url}, log.Field{Key: "args", Value: args})
	if reqbody, err = json.Marshal(args); err != nil {
		return
	}
	if req, err = http.NewRequestWithContext(ctx, method, url, bytes.NewBuffer(reqbody)); err != nil {
		return
	}
	req.Header.Set("Content-Type", "application/json")
	if resp, err = this.client.Do(req); err != nil {
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		err = fmt.Errorf("req fail StatusCode:%d", resp.StatusCode)
	} else {
		if respbody, err = io.ReadAll(resp.Body); err != nil {
			return
		}
		err = json.Unmarshal(respbody, result)
	}
	return
}
