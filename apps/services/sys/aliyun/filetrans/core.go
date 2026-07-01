package filetrans

type (
	ISys interface {
		// CreateTask 提交录音文件转写任务（异步）。callbackURL 为回调地址，回调 body 仅含固定字段（无自定义参数），用 task_id 匹配记录。
		CreateTask(audioURL, language string, enableSpeaker bool, callbackURL string) (taskID string, err error)
		// QueryTask 查询任务状态及结果
		QueryTask(taskID string) (status string, contexts []ContextStruct, err error)
	}

	// ContextStruct 转写结果片段
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
