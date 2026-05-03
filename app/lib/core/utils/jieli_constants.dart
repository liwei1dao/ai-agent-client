/// 杰里(Jieli)设备相关常量定义
/// 用于标准化系统属性类型和功能码

/// 系统属性类型常量
class JieliAttrType {
  // 公共属性
  static const int VOLUME = 1;                     // 音量
  static const int PLAYING_TIME = 2;               // 播放时间 
  static const int BATTERY_LEVEL = 3;              // 电池电量
  static const int WORK_MODE = 4;                  // 工作模式
  static const int PLAYBACK_MODE = 5;              // 播放模式(循环模式)
  static const int EQ_MODE = 6;                    // EQ模式
  static const int LANGUAGE = 7;                   // 语言设置
  static const int CONTRAST = 8;                   // 对比度
  static const int LED_ONOFF = 9;                  // LED开关
  static const int POWER_OFF_TIME = 10;            // 关机时间
  static const int LIGHT_ONOFF = 11;               // 背光开关
  static const int BLETYPE_SETTING = 12;           // BLE类型设置
  static const int TIME_OUT = 13;                  // 超时设置
  static const int DEVICE_NAME = 14;               // 设备名称
  static const int ALARM_ENABLE = 15;              // 闹钟开关
  static const int DEV_MAC = 16;                   // 设备MAC地址
  
  // 音乐相关属性
  static const int MUSIC_STATUS = 20;              // 音乐状态
  static const int MUSIC_CURR_DEVICE = 21;         // 当前音乐设备
  static const int MUSIC_TOTAL_TIME = 22;          // 音乐总时长
  static const int MUSIC_CURR_PLAY_TIME = 23;      // 当前播放时间
  static const int MUSIC_NUM = 24;                 // 音乐数量
  static const int MUSIC_DEV_STATUS = 25;          // 设备存储状态
  static const int MUSIC_BREAK_POINT = 26;         // 断点信息
  static const int MUSIC_CURR_FILENUM = 27;        // 当前文件编号
  static const int MUSIC_TOTAL_FILENUM = 28;       // 总文件数
  static const int MEDIA_TIMESTAMP = 29;           // 媒体时间戳
  
  // 模式相关
  static const int CUR_MODE = 30;                  // 当前模式
  
  // TWS相关
  static const int TWS_CONN_STATUS = 60;           // TWS连接状态
  static const int LEFT_CHN_BAT = 61;              // 左耳电量
  static const int RIGHT_CHN_BAT = 62;             // 右耳电量
  static const int TWS_STATUS = 63;                // TWS状态 
}

/// 功能码
class JieliFunctionCode {
  static const int COMMON = 0;                     // 公共功能
  static const int MUSIC = 1;                      // 音乐功能
  static const int RADIO = 2;                      // 收音机功能
  static const int LINEIN = 3;                     // 线路输入功能
  static const int RTC = 4;                        // 时钟功能
  static const int BT = 5;                         // 蓝牙功能
  static const int PC = 6;                         // PC功能
  static const int RECORD = 7;                     // 录音功能
  static const int UDISK = 8;                      // U盘功能
  static const int TALK = 9;                       // 通话功能
  static const int PHOTO = 10;                     // 拍照功能
  static const int VIDEO = 11;                     // 视频功能
}

/// 音乐播放状态
class JieliMusicStatus {
  static const int STOP = 0;                       // 停止状态
  static const int PLAY = 1;                       // 播放状态
  static const int PAUSE = 2;                      // 暂停状态
  static const int FAST_FORWARD = 3;               // 快进状态
  static const int FAST_BACKWARD = 4;              // 快退状态
}

/// 循环播放模式
class JieliPlaybackMode {
  static const int ALL = 0;                        // 全部循环
  static const int FOLDER = 1;                     // 文件夹循环
  static const int ONE = 2;                        // 单曲循环
  static const int RANDOM = 3;                     // 随机播放
  static const int BROWSE = 4;                     // 浏览播放
}

/// EQ模式
class JieliEQMode {
  static const int NORMAL = 0;                     // 正常
  static const int ROCK = 1;                       // 摇滚
  static const int POP = 2;                        // 流行
  static const int CLASSIC = 3;                    // 经典
  static const int JAZZ = 4;                       // 爵士
  static const int COUNTRY = 5;                    // 乡村
  static const int CUSTOM = 6;                     // 自定义
} 