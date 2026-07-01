package audomodel

import (
	"bytes"
	"crypto/rand"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"path/filepath"
	"time"
)

// 复用连接池的 HTTP Client，避免每次调用都新建 TLS 连接。
// submit/query 走短超时（query 接口通常 <1s），recognize-flash 是同步接口允许较长超时。
var (
	sharedTransport = &http.Transport{
		TLSClientConfig:     &tls.Config{InsecureSkipVerify: true},
		MaxIdleConns:        100,
		MaxIdleConnsPerHost: 20,
		IdleConnTimeout:     90 * time.Second,
	}
	submitClient  = &http.Client{Timeout: 30 * time.Second, Transport: sharedTransport}
	queryClient   = &http.Client{Timeout: 10 * time.Second, Transport: sharedTransport}
	flashClient   = &http.Client{Timeout: 15 * time.Minute, Transport: sharedTransport}
)

// defaultBaseUrl 字节语音大模型(bigmodel)的固定公网端点；
// 配置未显式指定 BaseUrl 时回退到此值。
const defaultBaseUrl = "https://openspeech.bytedance.com/api/v3/auc/bigmodel"

func newSys(options Options) (sys *AudoModel, err error) {
	if options.BaseUrl == "" {
		options.BaseUrl = defaultBaseUrl
	}
	// 配置未显式指定时回退到长音频录音识别(bigmodel)的默认参数。
	// 注意:这些值必须非空——异步 CreateTask 的 X-Api-Resource-Id 头为空会被字节
	// 直接拒绝(45000000 / "get resource id empty")。ResourceId 与 QueryTask 保持一致。
	if options.ResourceId == "" {
		options.ResourceId = "volc.bigasr.auc"
	}
	if options.ModelName == "" {
		options.ModelName = "bigmodel"
	}
	if options.ModelVersion == "" {
		options.ModelVersion = "400"
	}
	sys = &AudoModel{
		options: options,
	}

	return
}

type AudoModel struct {
	options Options
}

// generateUUID generates a random UUID v4 string
// generateUUID 生成一个随机的UUID v4字符串
// Return: string (uuid)
func (this *AudoModel) generateUUID() string {
	u := make([]byte, 16)
	_, err := rand.Read(u)
	if err != nil {
		return ""
	}
	u[6] = (u[6] & 0x0f) | 0x40 // Version 4
	u[8] = (u[8] & 0x3f) | 0x80 // Variant is 10
	return fmt.Sprintf("%x-%x-%x-%x-%x", u[0:4], u[4:6], u[6:8], u[8:10], u[10:])
}

// 创建任务
// 参数:
//   - url: 音频文件的可下载地址
//   - callbackURL: 回调地址（可选），服务完成识别后会 POST 到此地址
//   - callbackData: 回调参数（可选），将随回调请求一并返回
//
// 返回值:
//   - taskID: 任务ID（使用请求头中的 X-Api-Request-Id）
//   - logID: 日志ID（X-Tt-Logid）
//   - err: 调用过程中产生的错误
//
// 异常:
//   - 当请求创建失败、网络调用失败、响应状态码非成功时返回错误
func (this *AudoModel) CreateTask(userId string, url string, enableSpeakerInfo bool, language, callbackURL, callbackData string) (taskID string, logID string, err error) {
	taskID = this.generateUUID()

	// Prepare the request payload
	// 准备请求载荷
	payload := SubmitRequestStruct{
		User: UserStruct{
			UID: userId,
		},
		Audio: AudioStruct{
			URL:      url,
			Language: language,
			Format:   filepath.Ext(url),
		},
		Request: RequestSettingsStruct{
			ModelName:          this.options.ModelName,
			ModelVersion:       this.options.ModelVersion,
			EnableChannelSplit: true,
			// EnableDDC:          true,
			EnableSpeakerInfo: enableSpeakerInfo,
			EnablePunc:        true,
			// EnableITN:          true,

			// Corpus: CorpusStruct{
			// 	CorrectTableName: "",
			// 	Context:          "",
			// },
		},
		Callback:     callbackURL,
		CallbackData: callbackData,
	}

	jsonData, err := json.Marshal(payload)
	if err != nil {
		return "", "", fmt.Errorf("json marshal error: %v", err)
	}
	// 兼容不同字段命名，确保回调参数被服务识别
	if callbackURL != "" || callbackData != "" {
		var extra map[string]interface{}
		_ = json.Unmarshal(jsonData, &extra)
		if reqObj, ok := extra["request"].(map[string]interface{}); ok {
			if callbackURL != "" {
				reqObj["callback"] = callbackURL
				reqObj["callback_url"] = callbackURL
			}
			if callbackData != "" {
				reqObj["callback_data"] = callbackData
			}
			extra["request"] = reqObj
			jsonData, _ = json.Marshal(extra)
		}
	}

	req, err := http.NewRequest("POST", fmt.Sprintf("%s/%s", this.options.BaseUrl, "submit"), bytes.NewBuffer(jsonData))
	if err != nil {
		return "", "", fmt.Errorf("create request error: %v", err)
	}
	// Set headers
	// 设置请求头
	req.Header.Set("X-Api-App-Key", this.options.AppID)
	req.Header.Set("X-Api-Access-Key", this.options.Token)
	req.Header.Set("X-Api-Resource-Id", this.options.ResourceId)
	req.Header.Set("X-Api-Request-Id", taskID)
	req.Header.Set("X-Api-Sequence", "-1")
	req.Header.Set("Content-Type", "application/json")

	// log.Debugf("Submit task id: %s\n", taskID)

	resp, err := submitClient.Do(req)
	if err != nil {
		return "", "", fmt.Errorf("request failed: %v", err)
	}
	defer resp.Body.Close()

	// Check response headers
	// 检查响应头
	statusCode := resp.Header.Get("X-Api-Status-Code")
	if statusCode == "20000000" {
		// log.Debugf("Submit task response header X-Api-Status-Code: %s\n", statusCode)
		// log.Debugf("Submit task response header X-Api-Message: %s\n", resp.Header.Get("X-Api-Message"))
		xTtLogid := resp.Header.Get("X-Tt-Logid")
		// log.Debugf("Submit task response header X-Tt-Logid: %s\n\n", xTtLogid)
		return taskID, xTtLogid, nil
	}

	// log.Debugf("Submit task failed and the response headers are: %v\n", resp.Header)
	// Read body for more info if needed
	// body, _ := io.ReadAll(resp.Body)
	// log.Debugf("Response Body: %s\n", string(body))
	return "", "", fmt.Errorf("submit task failed with status code: %s", statusCode)
}

// queryTask checks the status of the submitted task
// QueryTask 查询已提交任务的状态
// Params: taskID (string), xTtLogid (string)
// Return: statusCode (string), contexts ([]*ContextStruct), error
func (this *AudoModel) QueryTask(taskID, xTtLogid string) (code string, contexts []*ContextStruct, err error) {
	req, err := http.NewRequest("POST", fmt.Sprintf("%s/%s", this.options.BaseUrl, "query"), bytes.NewBuffer([]byte("{}")))
	if err != nil {
		return "", nil, fmt.Errorf("create request error: %v", err)
	}
	// Set headers
	// 设置请求头
	req.Header.Set("X-Api-App-Key", this.options.AppID)
	req.Header.Set("X-Api-Access-Key", this.options.Token)
	req.Header.Set("X-Api-Resource-Id", "volc.bigasr.auc")
	req.Header.Set("X-Api-Request-Id", taskID)
	req.Header.Set("X-Tt-Logid", xTtLogid)
	req.Header.Set("Content-Type", "application/json")

	resp, err := queryClient.Do(req)
	if err != nil {
		return "", nil, fmt.Errorf("request failed: %v", err)
	}
	defer resp.Body.Close()

	body, readErr := io.ReadAll(resp.Body)

	code = resp.Header.Get("X-Api-Status-Code")
	apiMsg := resp.Header.Get("X-Api-Message")
	respLogID := resp.Header.Get("X-Tt-Logid")

	if code == "" {
		bodyPreview := string(body)
		if len(bodyPreview) > 512 {
			bodyPreview = bodyPreview[:512] + "...(truncated)"
		}
		return "", nil, fmt.Errorf("query task missing X-Api-Status-Code: http=%d headers=%v body=%q readErr=%v",
			resp.StatusCode, resp.Header, bodyPreview, readErr)
	}

	if readErr != nil {
		return code, nil, fmt.Errorf("read body failed: status=%s msg=%s logid=%s err=%v",
			code, apiMsg, respLogID, readErr)
	}

	if code != "20000000" {
		bodyPreview := string(body)
		if len(bodyPreview) > 512 {
			bodyPreview = bodyPreview[:512] + "...(truncated)"
		}
		err = fmt.Errorf("query task failed: status=%s msg=%s logid=%s http=%d body=%q",
			code, apiMsg, respLogID, resp.StatusCode, bodyPreview)
		return
	}
	// 使用结构体进行反序列化，并转换为 ContextStruct 列表
	var flashResp FlashResponseStruct
	if err = json.Unmarshal(body, &flashResp); err != nil {
		// 反序列化失败时，降级为返回原始JSON
		return
	}
	contexts = make([]*ContextStruct, 0, len(flashResp.Result.Utterances))
	for _, utt := range flashResp.Result.Utterances {
		contexts = append(contexts, &ContextStruct{
			Content:   utt.Text,
			StartTime: utt.StartTime,
			EndTime:   utt.EndTime,
			Speaker:   utt.Additions.Speaker,
		})
	}
	return
}

// RecognizeFlash 极速版识别（flash），通过音频URL立即返回识别结果
// 参数:
//   - url: 音频文件的可下载地址
//
// 返回值:
//   - statusCode: 响应头中的状态码（如 20000000 表示成功）
//   - logID: 响应头中的日志 ID（X-Tt-Logid）
//   - contexts: 识别出的语句片段列表（文本、起止时间、说话人）
//   - err: 调用过程中产生的错误
//
// 异常:
//   - 当请求创建失败、网络调用失败、响应缺少状态码或返回错误状态码时返回错误
func (this *AudoModel) RecognizeFlash(userId string, url string, enableSpeakerInfo bool, language string) (statusCode string, logID string, contexts []*ContextStruct, err error) {
	// 组装请求载荷（最小实现，仅支持 URL）
	reqPayload := map[string]interface{}{
		"user": map[string]interface{}{
			"uid": userId,
		},
		"audio": map[string]interface{}{
			"url":      url,
			"language": language,
		},
		"request": map[string]interface{}{
			"model_name": "bigmodel",
			// "enable_channel_split": true,
			"enable_itn":          true,
			"enable_punc":         true,
			"enable_ddc":          true,
			"enable_speaker_info": enableSpeakerInfo,
			"word_info":           1,
			"show_utterances":     true,
		},
	}
	jsonData, err := json.Marshal(reqPayload)
	if err != nil {
		return "", "", nil, fmt.Errorf("json marshal error: %v", err)
	}

	requestID := this.generateUUID()
	req, err := http.NewRequest("POST", fmt.Sprintf("%s/%s", this.options.BaseUrl, "recognize/flash"), bytes.NewBuffer(jsonData))
	if err != nil {
		return "", "", nil, fmt.Errorf("create request error: %v", err)
	}
	// req.Host = fmt.Sprintf("%s/%s", this.options.BaseUrl, "recognize/flash")
	req.Header.Set("X-Api-App-Key", this.options.AppID)
	req.Header.Set("X-Api-Access-Key", this.options.Token)
	req.Header.Set("X-Api-Resource-Id", "volc.bigasr.auc_turbo")
	req.Header.Set("X-Api-Request-Id", requestID)
	req.Header.Set("X-Api-Sequence", "-1")
	req.Header.Set("Content-Type", "application/json")

	resp, err := flashClient.Do(req)
	if err != nil {
		return "", "", nil, fmt.Errorf("request failed: %v", err)
	}
	defer resp.Body.Close()

	statusCode = resp.Header.Get("X-Api-Status-Code")
	logID = resp.Header.Get("X-Tt-Logid")
	if statusCode == "" {
		return "", "", nil, fmt.Errorf("recognize failed, missing status code")
	}
	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		return statusCode, logID, nil, err
	}
	if statusCode != "20000000" {
		return statusCode, logID, nil, fmt.Errorf("recognize failed with status code: %s", statusCode)
	}
	// 使用结构体进行反序列化，并转换为 ContextStruct 列表
	var flashResp FlashResponseStruct
	if err := json.Unmarshal(raw, &flashResp); err != nil {
		// 反序列化失败时，降级为返回原始JSON
		return statusCode, logID, []*ContextStruct{{Content: string(raw)}}, nil
	}
	contexts = make([]*ContextStruct, 0, len(flashResp.Result.Utterances))
	for _, utt := range flashResp.Result.Utterances {
		contexts = append(contexts, &ContextStruct{
			Content:   utt.Text,
			StartTime: utt.StartTime,
			EndTime:   utt.EndTime,
			Speaker:   utt.Additions.Speaker,
		})
	}
	return statusCode, logID, contexts, nil
}
