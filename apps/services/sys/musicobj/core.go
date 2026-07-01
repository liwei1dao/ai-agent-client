package musicobj

type (
	SearchResultResponse struct {
		Msg  string `json:"msg"`
		Data struct {
			Musics []struct {
				Id     int64  `json:"id"`
				Name   string `json:"name"`
				Image  string `json:"image"`
				Singer string `json:"singer"`
			} `json:"musics"`
		} `json:"data"`
		Code int `json:"code"`
	}
	UrlResultResponse struct {
		Msg  string `json:"msg"`
		Data struct {
			Id  int64  `json:"id"`
			URL string `json:"url"`
			Ts  int64  `json:"ts"`
		} `json:"data"`
		Code int `json:"code"`
	}

	ISys interface {
		SearchMusic(keywords string, limit, offset int) (result *SearchResultResponse, err error)
		MusicUrl(id int64) (result *UrlResultResponse, err error)
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

func SearchMusic(keywords string, limit, offset int) (result *SearchResultResponse, err error) {
	return defsys.SearchMusic(keywords, limit, offset)
}

func MusicUrl(id int64) (result *UrlResultResponse, err error) {
	return defsys.MusicUrl(id)
}
