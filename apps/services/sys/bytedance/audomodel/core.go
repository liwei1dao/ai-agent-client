package audomodel

type (
	ISys interface {
		CreateTask(userId string, url string, enableSpeakerInfo bool, language, callbackURL, callbackData string) (taskID string, logID string, err error)
		QueryTask(taskID, xTtLogid string) (statusCode string, contexts []*ContextStruct, err error)
		RecognizeFlash(userId string, url string, enableSpeakerInfo bool, language string) (statusCode string, logID string, contexts []*ContextStruct, err error)
	}

	// UserStruct represents the user information in the request
	// 用户信息结构体
	UserStruct struct {
		UID string `json:"uid"`
	}

	// AudioStruct represents the audio file information
	// 音频信息结构体
	AudioStruct struct {
		URL      string `json:"url"`
		Language string `json:"language"`
		Format   string `json:"format"`
	}

	// CorpusStruct represents corpus related settings
	// 语料库相关设置结构体
	CorpusStruct struct {
		CorrectTableName string `json:"correct_table_name"`
		Context          string `json:"context"`
	}

	// RequestSettingsStruct represents the specific request parameters
	// 请求参数设置结构体
	RequestSettingsStruct struct {
		ModelName          string       `json:"model_name"`
		ModelVersion       string       `json:"model_version"`
		EnableChannelSplit bool         `json:"enable_channel_split"`
		EnableDDC          bool         `json:"enable_ddc"`
		EnableSpeakerInfo  bool         `json:"enable_speaker_info"`
		EnablePunc         bool         `json:"enable_punc"`
		EnableITN          bool         `json:"enable_itn"`
		Corpus             CorpusStruct `json:"corpus"`
	}

	// SubmitRequestStruct represents the full payload for the submit task
	// 提交任务的完整请求结构体
	SubmitRequestStruct struct {
		User         UserStruct            `json:"user"`
		Audio        AudioStruct           `json:"audio"`
		Request      RequestSettingsStruct `json:"request"`
		Callback     string                `json:"callback,omitempty"`
		CallbackData string                `json:"callback_data,omitempty"`
	}
	// ContextStruct represents a minimal transcript segment
	// 识别结果最小结构：文本片段与可选的时间与说话人
	ContextStruct struct {
		Content   string `json:"content"`
		StartTime int64  `json:"start_time,omitempty"`
		EndTime   int64  `json:"end_time,omitempty"`
		Speaker   string `json:"speaker,omitempty"`
	}

	// FlashResponseStruct 极速版返回的数据结构
	FlashResponseStruct struct {
		AudioInfo struct {
			Duration int64 `json:"duration"`
		} `json:"audio_info"`
		Result struct {
			Additions struct {
				Duration string `json:"duration"`
			} `json:"additions"`
			Text       string `json:"text"`
			Utterances []struct {
				EndTime   int64  `json:"end_time"`
				StartTime int64  `json:"start_time"`
				Text      string `json:"text"`
				Words     []struct {
					Confidence float64 `json:"confidence"`
					EndTime    int64   `json:"end_time"`
					StartTime  int64   `json:"start_time"`
					Text       string  `json:"text"`
				} `json:"words"`
				Additions struct {
					ChannelID string `json:"channel_id"`
					Speaker   string `json:"speaker"`
				} `json:"additions,omitempty"`
			} `json:"utterances"`
		} `json:"result"`
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
func CreateTask(userId string, url string, enableSpeakerInfo bool, language, callbackURL, callbackData string) (taskID string, logID string, err error) {
	return defsys.CreateTask(userId, url, enableSpeakerInfo, language, callbackURL, callbackData)
}
func QueryTask(taskID, xTtLogid string) (statusCode string, contexts []*ContextStruct, err error) {
	return defsys.QueryTask(taskID, xTtLogid)
}
func RecognizeFlash(userId string, url string, enableSpeakerInfo bool, language string) (statusCode string, logID string, contexts []*ContextStruct, err error) {
	return defsys.RecognizeFlash(userId, url, enableSpeakerInfo, language)
}
