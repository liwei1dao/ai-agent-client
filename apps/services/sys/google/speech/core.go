package speech

type (
	ISys interface {
		// CreateTask 提交长音频转写任务（异步，返回 operation name 作为 taskID）。
		// audioURL 必须是 gs:// 形式的 GCS URI；公网 http(s) URL 由调用方在外层先上传到 GCS。
		// callbackURL 当前未使用，调用方通过 QueryTask 轮询。
		CreateTask(audioURL, language string, enableSpeaker bool, callbackURL string) (taskID string, err error)
		// QueryTask 查询 LRO 状态及结果。taskID 为 CreateTask 返回的 operation name 全路径。
		QueryTask(taskID string) (status string, contexts []ContextStruct, err error)
	}

	// ContextStruct 转写结果片段，对齐 sys/aliyun/filetrans 与 sys/microsoft/speech
	ContextStruct struct {
		Content   string `json:"content"`
		StartTime int64  `json:"start_time"`
		EndTime   int64  `json:"end_time"`
		Speaker   string `json:"speaker,omitempty"`
	}
)

// 任务状态常量
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
