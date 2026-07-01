package migu

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

func newSys(options Options) (sys *Migu, err error) {
	sys = &Migu{
		options: options,
	}
	return
}

type Migu struct {
	options Options
}

// Chat 以流式方式请求咪咕灵犀，逐条解析 SSE 数据写入 ch；无论成功失败，结束时都会关闭 ch。
func (this *Migu) Chat(ctx context.Context, req *Request, ch chan *StreamResp) (err error) {
	defer close(ch)
	var body []byte

	// 强制流式
	req.Stream = true
	if req.DeviceId == "" {
		req.DeviceId = this.options.DefaultDeviceId
	}
	if body, err = json.Marshal(req); err != nil {
		return
	}

	// 用 context 控制整个流式请求的生命周期
	ctx, cancel := context.WithTimeout(ctx, time.Duration(this.options.TimeoutSecond)*time.Second)
	defer cancel()

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, this.options.BaseURL, bytes.NewReader(body))
	if err != nil {
		return
	}
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Accept", "text/event-stream")
	for k, v := range this.options.Headers {
		httpReq.Header.Set(k, v)
	}

	client := &http.Client{Timeout: 0} // 不用 client 超时，统一交给 context
	resp, err := client.Do(httpReq)
	if err != nil {
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		data, _ := io.ReadAll(resp.Body)
		err = fmt.Errorf("migu lingxi http status=%d body=%s", resp.StatusCode, string(data))
		this.options.Log.Errorln(err)
		return
	}

	reader := bufio.NewReader(resp.Body)
	for {
		select {
		case <-ctx.Done():
			err = ctx.Err()
			return
		default:
		}

		line, e := reader.ReadBytes('\n')
		if len(line) > 0 {
			trimmed := bytes.TrimSpace(line)
			if len(trimmed) > 0 && bytes.HasPrefix(trimmed, []byte("data:")) {
				payload := bytes.TrimSpace(bytes.TrimPrefix(trimmed, []byte("data:")))
				// 结束标语 data:[DONE]
				if len(payload) == 0 || bytes.Equal(payload, []byte("[DONE]")) {
					return
				}
				var sr StreamResp
				if jerr := json.Unmarshal(payload, &sr); jerr != nil {
					// 单行解析失败不中断整个流，记录后跳过
					this.options.Log.Errorf("migu lingxi unmarshal chunk err: %v, raw=%s", jerr, string(payload))
				} else {
					ch <- &sr
				}
			}
		}

		if e != nil {
			if e == io.EOF {
				return
			}
			err = e
			return
		}
	}
}
