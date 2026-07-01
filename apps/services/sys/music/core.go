package music

type (

	// MusicResponse 顶层响应结构
	SearchResultResponse struct {
		Result struct {
			SearchQcReminder interface{} `json:"searchQcReminder"`
			Songs            []struct {
				Name string     `json:"name"`
				Id   int64      `json:"id"`
				Pst  int        `json:"pst"`
				T    int        `json:"t"`
				Ar   []struct { // 内嵌艺术家结构
					Id    int64    `json:"id"`
					Name  string   `json:"name"`
					Tns   []string `json:"tns"`
					Alias []string `json:"alias"`
					Alia  []string `json:"alia"`
				} `json:"ar"`
				Alia []string    `json:"alia"`
				Pop  int         `json:"pop"`
				St   int         `json:"st"`
				Rt   string      `json:"rt"`
				Fee  int         `json:"fee"`
				V    int         `json:"v"`
				Crbt interface{} `json:"crbt"`
				Cf   string      `json:"cf"`
				Al   struct {    // 内嵌专辑结构
					Id     int64    `json:"id"`
					Name   string   `json:"name"`
					PicUrl string   `json:"picUrl"`
					Tns    []string `json:"tns"`
					PicStr string   `json:"pic_str"`
					Pic    int64    `json:"pic"`
				} `json:"al"`
				Dt int      `json:"dt"`
				H  struct { // 内嵌高品质音频信息
					Br   int `json:"br"`
					Fid  int `json:"fid"`
					Size int `json:"size"`
					Vd   int `json:"vd"`
					Sr   int `json:"sr"`
				} `json:"h"`
				M struct { // 内嵌中品质音频信息
					Br   int `json:"br"`
					Fid  int `json:"fid"`
					Size int `json:"size"`
					Vd   int `json:"vd"`
					Sr   int `json:"sr"`
				} `json:"m"`
				L struct { // 内嵌低品质音频信息
					Br   int `json:"br"`
					Fid  int `json:"fid"`
					Size int `json:"size"`
					Vd   int `json:"vd"`
					Sr   int `json:"sr"`
				} `json:"l"`
				Sq struct { // 内嵌无损品质音频信息
					Br   int `json:"br"`
					Fid  int `json:"fid"`
					Size int `json:"size"`
					Vd   int `json:"vd"`
					Sr   int `json:"sr"`
				} `json:"sq"`
				Hr struct { // 内嵌高清品质音频信息
					Br   int `json:"br"`
					Fid  int `json:"fid"`
					Size int `json:"size"`
					Vd   int `json:"vd"`
					Sr   int `json:"sr"`
				} `json:"hr"`
				A                    interface{}   `json:"a"`
				Cd                   string        `json:"cd"`
				No                   int           `json:"no"`
				RtUrl                interface{}   `json:"rtUrl"`
				Ftype                int           `json:"ftype"`
				RtUrls               []interface{} `json:"rtUrls"`
				DjId                 int           `json:"djId"`
				Copyright            int           `json:"copyright"`
				SId                  int           `json:"s_id"`
				Mark                 int64         `json:"mark"`
				OriginCoverType      int           `json:"originCoverType"`
				OriginSongSimpleData interface{}   `json:"originSongSimpleData"`
				TagPicList           interface{}   `json:"tagPicList"`
				ResourceState        bool          `json:"resourceState"`
				Version              int           `json:"version"`
				SongJumpInfo         interface{}   `json:"songJumpInfo"`
				EntertainmentTags    interface{}   `json:"entertainmentTags"`
				Single               int           `json:"single"`
				NoCopyrightRcmd      interface{}   `json:"noCopyrightRcmd"`
				Rtype                int           `json:"rtype"`
				Rurl                 interface{}   `json:"rurl"`
				Mst                  int           `json:"mst"`
				Cp                   int           `json:"cp"`
				Mv                   int           `json:"mv"`
				PublishTime          int           `json:"publishTime"`
				Privilege            struct {      // 内嵌权限信息结构
					Id                 int64       `json:"id"`
					Fee                int         `json:"fee"`
					Payed              int         `json:"payed"`
					St                 int         `json:"st"`
					Pl                 int         `json:"pl"`
					Dl                 int         `json:"dl"`
					Sp                 int         `json:"sp"`
					Cp                 int         `json:"cp"`
					Subp               int         `json:"subp"`
					Cs                 bool        `json:"cs"`
					Maxbr              int         `json:"maxbr"`
					Fl                 int         `json:"fl"`
					Toast              bool        `json:"toast"`
					Flag               int         `json:"flag"`
					PreSell            bool        `json:"preSell"`
					PlayMaxbr          int         `json:"playMaxbr"`
					DownloadMaxbr      int         `json:"downloadMaxbr"`
					MaxBrLevel         string      `json:"maxBrLevel"`
					PlayMaxBrLevel     string      `json:"playMaxBrLevel"`
					DownloadMaxBrLevel string      `json:"downloadMaxBrLevel"`
					PlLevel            string      `json:"plLevel"`
					DlLevel            string      `json:"dlLevel"`
					FlLevel            string      `json:"flLevel"`
					Rscl               interface{} `json:"rscl"`
					FreeTrialPrivilege struct {    // 内嵌免费试用权限
						ResConsumable      bool        `json:"resConsumable"`
						UserConsumable     bool        `json:"userConsumable"`
						ListenType         interface{} `json:"listenType"`
						CannotListenReason interface{} `json:"cannotListenReason"`
						PlayReason         interface{} `json:"playReason"`
						FreeLimitTagType   interface{} `json:"freeLimitTagType"`
					} `json:"freeTrialPrivilege"`
					RightSource    int        `json:"rightSource"`
					ChargeInfoList []struct { // 内嵌收费信息列表
						Rate          int         `json:"rate"`
						ChargeUrl     interface{} `json:"chargeUrl"`
						ChargeMessage interface{} `json:"chargeMessage"`
						ChargeType    int         `json:"chargeType"`
					} `json:"chargeInfoList"`
					Code        int         `json:"code"`
					Message     interface{} `json:"message"`
					PlLevels    interface{} `json:"plLevels"`
					DlLevels    interface{} `json:"dlLevels"`
					IgnoreCache interface{} `json:"ignoreCache"`
					Bd          interface{} `json:"bd"`
				} `json:"privilege"`
			} `json:"songs"`
			SongCount int `json:"songCount"`
		} `json:"result"`
		Code int `json:"code"`
	}

	FreeTrialInfo struct {
		ResConsumable      bool        `json:"resConsumable"`
		UserConsumable     bool        `json:"userConsumable"`
		ListenType         interface{} `json:"listenType"`
		CannotListenReason interface{} `json:"cannotListenReason"`
		PlayReason         interface{} `json:"playReason"`
		FreeLimitTagType   interface{} `json:"freeLimitTagType"`
	}

	FreeTimeTrialPrivilege struct {
		ResConsumable  bool `json:"resConsumable"`
		UserConsumable bool `json:"userConsumable"`
		Type           int  `json:"type"`
		RemainTime     int  `json:"remainTime"`
	}

	UrlResult struct {
		Data struct {
			Size   int    `json:"size"`
			Br     int    `json:"br"`
			URL    string `json:"url"`
			MD5    string `json:"md5"`
			Source string `json:"source"`
		} `json:"data"`
		Code int `json:"code"`
	}
	//歌单搜索
	PlaylistSearchResponse struct {
		Code int `json:"code"` // 响应状态码

		Result struct {
			PlaylistCount    int         `json:"playlistCount"`    // 歌单总数
			HasMore          bool        `json:"hasMore"`          // 是否有更多数据
			HlWords          []string    `json:"hlWords"`          // 高亮词（通常为搜索关键词）
			SearchQcReminder interface{} `json:"searchQcReminder"` // 提示信息（暂无结构）

			Playlists []struct {
				ID            int64       `json:"id"`            // 歌单 ID
				Name          string      `json:"name"`          // 歌单名称
				CoverImgUrl   string      `json:"coverImgUrl"`   // 歌单封面图
				Subscribed    bool        `json:"subscribed"`    // 是否已收藏
				TrackCount    int         `json:"trackCount"`    // 歌曲数量
				UserId        int64       `json:"userId"`        // 创建者用户 ID
				PlayCount     int64       `json:"playCount"`     // 播放次数
				BookCount     int64       `json:"bookCount"`     // 收藏次数
				SpecialType   int         `json:"specialType"`   // 特殊标记（如官方歌单）
				Action        string      `json:"action"`        // 播放链接
				ActionType    string      `json:"actionType"`    // 动作类型
				RecommendText interface{} `json:"recommendText"` // 推荐文案（可能为空）
				Score         string      `json:"score"`         // 推荐分数（字符串）
				Description   string      `json:"description"`   // 歌单描述
				HighQuality   bool        `json:"highQuality"`   // 是否高品质歌单
				OfficialTags  []string    `json:"officialTags"`  // 官方标签

				Creator struct {
					Nickname   string      `json:"nickname"`   // 创建者昵称
					UserId     int64       `json:"userId"`     // 用户 ID
					UserType   int         `json:"userType"`   // 用户类型
					AvatarUrl  string      `json:"avatarUrl"`  // 用户头像
					AuthStatus int         `json:"authStatus"` // 认证状态
					ExpertTags interface{} `json:"expertTags"` // 专家标签（空或未知结构）
					Experts    interface{} `json:"experts"`    // 专家信息（空或未知结构）
				} `json:"creator"` // 创建者信息

				Track struct {
					Name        string   `json:"name"`        // 歌曲名称
					ID          int64    `json:"id"`          // 歌曲 ID
					Position    int      `json:"position"`    // 歌曲在歌单中的位置
					Alias       []string `json:"alias"`       // 别名
					Status      int      `json:"status"`      // 状态
					Fee         int      `json:"fee"`         // 费用
					CopyrightId int      `json:"copyrightId"` // 版权 ID
					Disc        string   `json:"disc"`        // 所属碟片
					No          int      `json:"no"`          // 曲目编号

					Artists []struct {
						Name        string   `json:"name"` // 歌手名
						ID          int64    `json:"id"`   // 歌手 ID
						PicId       int64    `json:"picId"`
						Img1v1Id    int64    `json:"img1v1Id"`
						BriefDesc   string   `json:"briefDesc"`
						PicUrl      string   `json:"picUrl"`
						Img1v1Url   string   `json:"img1v1Url"`
						AlbumSize   int      `json:"albumSize"`
						Alias       []string `json:"alias"`
						Trans       string   `json:"trans"`
						MusicSize   int      `json:"musicSize"`
						TopicPerson int      `json:"topicPerson"`
					} `json:"artists"` // 歌手列表

					Album struct {
						Name        string  `json:"name"`       // 专辑名称
						ID          int64   `json:"id"`         // 专辑 ID
						IdStr       *string `json:"idStr"`      // ID 字符串
						Type        string  `json:"type"`       // 类型
						Size        int     `json:"size"`       // 歌曲数
						PicId       int64   `json:"picId"`      // 封面图 ID
						BlurPicUrl  string  `json:"blurPicUrl"` // 模糊封面图
						CompanyId   int     `json:"companyId"`
						Pic         int64   `json:"pic"`
						PicUrl      string  `json:"picUrl"`
						PublishTime int64   `json:"publishTime"` // 发布时间
						Description string  `json:"description"` // 描述
						Tags        string  `json:"tags"`        // 标签
						Company     string  `json:"company"`     // 出版公司
						BriefDesc   string  `json:"briefDesc"`   // 简要描述

						Artist struct {
							Name        string   `json:"name"`
							ID          int64    `json:"id"`
							PicId       int64    `json:"picId"`
							Img1v1Id    int64    `json:"img1v1Id"`
							BriefDesc   string   `json:"briefDesc"`
							PicUrl      string   `json:"picUrl"`
							Img1v1Url   string   `json:"img1v1Url"`
							AlbumSize   int      `json:"albumSize"`
							Alias       []string `json:"alias"`
							Trans       string   `json:"trans"`
							MusicSize   int      `json:"musicSize"`
							TopicPerson int      `json:"topicPerson"`
						} `json:"artist"`

						Songs           []interface{} `json:"songs"` // 预留字段
						Alias           []string      `json:"alias"`
						Status          int           `json:"status"`
						CopyrightId     int           `json:"copyrightId"`
						CommentThreadId string        `json:"commentThreadId"`
						Artists         []struct {
							Name        string   `json:"name"`
							ID          int64    `json:"id"`
							PicId       int64    `json:"picId"`
							Img1v1Id    int64    `json:"img1v1Id"`
							BriefDesc   string   `json:"briefDesc"`
							PicUrl      string   `json:"picUrl"`
							Img1v1Url   string   `json:"img1v1Url"`
							AlbumSize   int      `json:"albumSize"`
							Alias       []string `json:"alias"`
							Trans       string   `json:"trans"`
							MusicSize   int      `json:"musicSize"`
							TopicPerson int      `json:"topicPerson"`
						} `json:"artists"`

						OnSale   bool   `json:"onSale"`
						PicIdStr string `json:"picId_str"`
					} `json:"album"`

					Starred         bool        `json:"starred"`
					Popularity      int         `json:"popularity"`
					Score           int         `json:"score"`
					StarredNum      int         `json:"starredNum"`
					Duration        int         `json:"duration"` // 时长（毫秒）
					PlayedNum       int         `json:"playedNum"`
					DayPlays        int         `json:"dayPlays"`
					HearTime        int         `json:"hearTime"`
					Ringtone        string      `json:"ringtone"`
					CRBT            interface{} `json:"crbt"`
					Audition        interface{} `json:"audition"`
					CopyFrom        string      `json:"copyFrom"`
					CommentThreadId string      `json:"commentThreadId"`
					RtUrl           interface{} `json:"rtUrl"`
					Ftype           int         `json:"ftype"`
					RtUrls          []string    `json:"rtUrls"`
					Copyright       int         `json:"copyright"`

					HMusic struct {
						Name        *string `json:"name"`
						ID          int64   `json:"id"`
						Size        int     `json:"size"`
						Extension   string  `json:"extension"`
						Sr          int     `json:"sr"`
						DfsId       int64   `json:"dfsId"`
						Bitrate     int     `json:"bitrate"`
						PlayTime    int     `json:"playTime"`
						VolumeDelta int     `json:"volumeDelta"`
					} `json:"hMusic"`

					MMusic struct {
						Name        *string `json:"name"`
						ID          int64   `json:"id"`
						Size        int     `json:"size"`
						Extension   string  `json:"extension"`
						Sr          int     `json:"sr"`
						DfsId       int64   `json:"dfsId"`
						Bitrate     int     `json:"bitrate"`
						PlayTime    int     `json:"playTime"`
						VolumeDelta int     `json:"volumeDelta"`
					} `json:"mMusic"`

					LMusic struct {
						Name        *string `json:"name"`
						ID          int64   `json:"id"`
						Size        int     `json:"size"`
						Extension   string  `json:"extension"`
						Sr          int     `json:"sr"`
						DfsId       int64   `json:"dfsId"`
						Bitrate     int     `json:"bitrate"`
						PlayTime    int     `json:"playTime"`
						VolumeDelta int     `json:"volumeDelta"`
					} `json:"lMusic"`

					BMusic struct {
						Name        *string `json:"name"`
						ID          int64   `json:"id"`
						Size        int     `json:"size"`
						Extension   string  `json:"extension"`
						Sr          int     `json:"sr"`
						DfsId       int64   `json:"dfsId"`
						Bitrate     int     `json:"bitrate"`
						PlayTime    int     `json:"playTime"`
						VolumeDelta int     `json:"volumeDelta"`
					} `json:"bMusic"`

					Mvid   int         `json:"mvid"`
					Rtype  int         `json:"rtype"`
					Rurl   interface{} `json:"rurl"`
					Mp3Url interface{} `json:"mp3Url"`
				} `json:"track"`

				Alg string `json:"alg"` // 推荐算法字段
			} `json:"playlists"`
		} `json:"result"`
	}

	SongResponse struct {
		Songs []struct {
			Name            string  `json:"name"`            // 歌曲名称
			MainTitle       *string `json:"mainTitle"`       // 主标题
			AdditionalTitle *string `json:"additionalTitle"` // 附加标题
			ID              int     `json:"id"`              // 歌曲 ID
			Pst             int     `json:"pst"`             // 排序字段
			T               int     `json:"t"`               // 类型字段
			Ar              []struct {
				ID    int      `json:"id"`     // 歌手 ID
				Name  string   `json:"name"`   // 歌手名
				Tns   []string `json:"tns"`    // 翻译名
				Alias []string `json:"alias "` // 别名
			} `json:"ar"`
			Alia []string `json:"alia"` // 歌曲别名
			Pop  int      `json:"pop"`  // 热度
			St   int      `json:"st"`   // 状态码
			Rt   string   `json:"rt"`   // 资源标识
			Fee  int      `json:"费用"`   // 是否收费
			V    int      `json:"v "`   // 版本
			Crbt *string  `json:"crbt"` // 彩铃信息
			Cf   string   `json:"cf"`   // 未知字段
			Al   struct {
				ID     int      `json:"id"`      // 专辑 ID
				Name   string   `json:"name"`    // 专辑名
				PicURL string   `json:"picUrl"`  // 专辑封面
				Tns    []string `json:"tns"`     // 翻译名
				PicStr string   `json:"pic_str"` // 图片字符串 ID
				Pic    int64    `json:"pic"`     // 图片 ID
			} `json:"al"`
			Dt int `json:"dt"` // 时长（毫秒）

			H  struct{ Br, Fid, Size, Vd, Sr int } `json:"h"`  // 高音质
			M  struct{ Br, Fid, Size, Vd, Sr int } `json:"m"`  // 中音质
			L  struct{ Br, Fid, Size, Vd, Sr int } `json:"l"`  // 低音质
			Sq struct{ Br, Fid, Size, Vd, Sr int } `json:"sq"` // 无损音质

			Hr                   interface{} `json:"hr"`
			A                    *string     `json:"a"`
			Cd                   string      `json:"cd"`
			No                   int         `json:"no"`
			RtUrl                *string     `json:"rtUrl"`
			Ftype                int         `json:"ftype"`
			RtUrls               []string    `json:"rtUrls"`
			DjId                 int         `json:"djId"`
			Copyright            int         `json:"copyright"`
			SId                  int         `json:"s_id"`
			Mark                 int64       `json:"mark"`
			OriginCoverType      int         `json:"originCoverType"`
			Tns                  []string    `json:"tns"`
			OriginSongSimpleData interface{} `json:"originSongSimpleData"`
			TagPicList           *string     `json:"tagPicList"`
			ResourceState        bool        `json:"resourceState"`
			Version              int         `json:"version"`
			SongJumpInfo         *string     `json:"songJumpInfo"`
			EntertainmentTags    *string     `json:"entertainmentTags"`
			AwardTags            *string     `json:"awardTags"`
			DisplayTags          *string     `json:"displayTags"`
			Single               int         `json:"single"`
			NoCopyrightRcmd      *string     `json:"noCopyrightRcmd"`
			Mv                   int         `json:"mv"`
			Rtype                int         `json:"rtype"`
			Rurl                 *string     `json:"rurl"`
			Mst                  int         `json:"mst"`
			Cp                   int         `json:"cp"`
			PublishTime          int64       `json:"publishTime"`
		} `json:"songs"`

		Privileges []struct {
			ID                 int         `json:"id"`
			Fee                int         `json:"fee"`
			Payed              int         `json:"payed"`
			St                 int         `json:"st"`
			Pl                 int         `json:"pl"`
			Dl                 int         `json:"dl"`
			Sp                 int         `json:"sp"`
			Cp                 int         `json:"cp"`
			Subp               int         `json:"subp"`
			Cs                 bool        `json:"cs"`
			Maxbr              int         `json:"maxbr"`
			Fl                 int         `json:"fl"`
			Toast              bool        `json:"toast"`
			Flag               int         `json:"flag"`
			PreSell            bool        `json:"preSell"`
			PlayMaxbr          int         `json:"playMaxbr"`
			DownloadMaxbr      int         `json:"downloadMaxbr"`
			MaxBrLevel         string      `json:"maxBrLevel"`
			PlayMaxBrLevel     string      `json:"playMaxBrLevel"`
			DownloadMaxBrLevel string      `json:"downloadMaxBrLevel"`
			PlLevel            string      `json:"plLevel"`
			DlLevel            string      `json:"dlLevel"`
			FlLevel            string      `json:"flLevel"`
			Rscl               interface{} `json:"rscl"`
			FreeTrialPrivilege struct {
				ResConsumable      bool        `json:"resConsumable"`
				UserConsumable     bool        `json:"userConsumable"`
				ListenType         interface{} `json:"listenType"`
				CannotListenReason interface{} `json:"cannotListenReason"`
				PlayReason         interface{} `json:"playReason"`
				FreeLimitTagType   interface{} `json:"freeLimitTagType"`
			} `json:"freeTrialPrivilege"`
			RightSource    int `json:"rightSource"`
			ChargeInfoList []struct {
				Rate          int         `json:"rate"`
				ChargeUrl     interface{} `json:"chargeUrl"`
				ChargeMessage interface{} `json:"chargeMessage"`
				ChargeType    int         `json:"chargeType"`
			} `json:"chargeInfoList"`
			Code    int     `json:"code"`
			Message *string `json:"message"`
		} `json:"privileges"`

		Code int `json:"code"` // 响应状态码
	}
	//播放列表详情回复
	MusicListDetailResponse struct {
		Code int `json:"code"` // 响应状态码

		Songs []struct {
			Name            string  `json:"name"`            // 歌曲名称
			MainTitle       *string `json:"mainTitle"`       // 主标题（可选）
			AdditionalTitle *string `json:"additionalTitle"` // 副标题（可选）
			ID              int64   `json:"id"`              // 歌曲 ID
			Pst             int     `json:"pst"`
			T               int     `json:"t"`

			Ar []struct {
				ID    int64    `json:"id"`    // 歌手 ID
				Name  string   `json:"name"`  // 歌手名称
				Tns   []string `json:"tns"`   // 翻译名
				Alias []string `json:"alias"` // 别名
			} `json:"ar"` // 歌手列表

			Al struct {
				ID     int64    `json:"id"`      // 专辑 ID
				Name   string   `json:"name"`    // 专辑名称
				PicURL string   `json:"picUrl"`  // 专辑封面 URL
				PicStr string   `json:"pic_str"` // 封面图字符串
				Pic    int64    `json:"pic"`     // 封面图 ID
				Tns    []string `json:"tns"`     // 专辑翻译名
			} `json:"al"` // 专辑信息

			Pop int `json:"pop"` // 热度

			Fee int `json:"fee"` // 版权费用标记

			DT int `json:"dt"` // 时长（单位：毫秒）

			H struct {
				Br   int `json:"br"`   // 码率
				Size int `json:"size"` // 文件大小（字节）
				Vd   int `json:"vd"`   // 音量动态
				Sr   int `json:"sr"`   // 采样率
				Fid  int `json:"fid"`  // 文件 ID
			} `json:"h"` // 高音质

			M struct {
				Br   int `json:"br"`
				Size int `json:"size"`
				Vd   int `json:"vd"`
				Sr   int `json:"sr"`
				Fid  int `json:"fid"`
			} `json:"m"` // 中音质

			L struct {
				Br   int `json:"br"`
				Size int `json:"size"`
				Vd   int `json:"vd"`
				Sr   int `json:"sr"`
				Fid  int `json:"fid"`
			} `json:"l"` // 低音质

			SQ *struct {
				Br   int `json:"br"`
				Size int `json:"size"`
				Vd   int `json:"vd"`
				Sr   int `json:"sr"`
				Fid  int `json:"fid"`
			} `json:"sq,omitempty"` // 超高音质（可选）

			MV          int      `json:"mv"`          // MV ID
			PublishTime int64    `json:"publishTime"` // 发布时间（时间戳）
			Tns         []string `json:"tns"`         // 歌曲翻译名
		} `json:"songs"`

		Privileges []struct {
			ID    int64 `json:"id"`    // 歌曲 ID
			Fee   int   `json:"fee"`   // 收费类型
			Payed int   `json:"payed"` // 是否已付费
			ST    int   `json:"st"`    // 状态码
			Pl    int   `json:"pl"`    // 播放权限
			Dl    int   `json:"dl"`    // 下载权限
			Sp    int   `json:"sp"`    // 播放标记
			Cp    int   `json:"cp"`    // 复制权限
			Subp  int   `json:"subp"`  // 订阅权限
			Maxbr int   `json:"maxbr"` // 最大码率
			Flag  int   `json:"flag"`  // 标记位
			Fl    int   `json:"fl"`    // 免费播放标记

			ChargeInfoList []struct {
				Rate       int    `json:"rate"`          // 码率
				ChargeType int    `json:"chargeType"`    // 收费类型
				ChargeUrl  string `json:"chargeUrl"`     // 收费链接（一般为空）
				ChargeMsg  string `json:"chargeMessage"` // 提示信息（一般为空）
			} `json:"chargeInfoList"` // 收费信息列表

			FreeTrialPrivilege struct {
				ResConsumable      bool        `json:"resConsumable"`      // 资源是否可消费
				UserConsumable     bool        `json:"userConsumable"`     // 用户是否可试听
				ListenType         interface{} `json:"listenType"`         // 听歌类型（可空）
				CannotListenReason interface{} `json:"cannotListenReason"` // 无法播放原因（可空）
			} `json:"freeTrialPrivilege"` // 试听权限设置
		} `json:"privileges"`
	}

	ISys interface {
		SearchMusic(keywords string, limit, offset int) (result *SearchResultResponse, err error)
		SearchMusicList(keywords string, limit, offset int) (result *PlaylistSearchResponse, err error)
		MusicListDetail(id int64, limit, offset int) (result *MusicListDetailResponse, err error)
		MusicUrl(id int64) (result *UrlResult, err error)
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

func SearchMusicList(keywords string, limit, offset int) (result *PlaylistSearchResponse, err error) {
	return defsys.SearchMusicList(keywords, limit, offset)
}

func MusicListDetail(id int64, limit, offset int) (result *MusicListDetailResponse, err error) {
	return defsys.MusicListDetail(id, limit, offset)
}

func MusicUrl(id int64) (result *UrlResult, err error) {
	return defsys.MusicUrl(id)
}
