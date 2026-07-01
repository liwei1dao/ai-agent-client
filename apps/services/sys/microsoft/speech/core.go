package speech

type (
	ISys interface {
		// CreateTask 提交录音文件转写任务（异步）。callbackURL 当前由调用方在拿到 taskID 后自行轮询；
		// 如需 webhook，请走 Azure /speechtotext/v3.2/webhooks 单独注册后将 taskID 与回调匹配。
		CreateTask(audioURL, language string, enableSpeaker bool, callbackURL string) (taskID string, err error)
		// QueryTask 查询任务状态及结果
		QueryTask(taskID string) (status string, contexts []ContextStruct, err error)
	}

	// ContextStruct 转写结果片段，对齐 sys/aliyun/filetrans 与 sys/bytedance/audomodel
	ContextStruct struct {
		Content   string `json:"content"`
		StartTime int64  `json:"start_time"`
		EndTime   int64  `json:"end_time"`
		Speaker   string `json:"speaker,omitempty"`
	}
)

// 任务状态常量，对齐 sys/aliyun/filetrans
const (
	StatusRunning = "RUNNING"
	StatusSuccess = "SUCCESS"
	StatusFailed  = "FAILED"
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

func CreateTask(audioURL, language string, enableSpeaker bool, callbackURL string) (taskID string, err error) {
	return defsys.CreateTask(audioURL, language, enableSpeaker, callbackURL)
}

func QueryTask(taskID string) (status string, contexts []ContextStruct, err error) {
	return defsys.QueryTask(taskID)
}
