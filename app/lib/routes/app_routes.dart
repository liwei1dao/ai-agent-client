abstract class Routes {
  // 认证相关
  static const splash = '/splash';
  static const login = '/login';

  // 主功能模块
  static const initial = '/home';
  static const home = '/home';
  static const explore = '/explore';
  static const chat = '/chat';
  static const profile = '/profile';
  static const editProfile = '/edit_profile';
  static const profileMeeting = '/profile_meeting'; // 个人信息页面（从会议模块跳转）

  // 设备管理
  static const OTA_UPGRADE = '/ota_upgrade'; // OTA升级
  static const timbre = '/timbre'; // 音色设置
  static const voiceReplication = '/voice_replication'; // 声音复刻
  static const settings = '/settings'; // 系统设置
  static const permissions = '/permissions'; // 权限管理
  static const recording = '/recording'; // 录音功能
  static const eqSettings = '/eq_settings'; // 设备设置

  // 会议相关
  static const meeting = '/meeting';
  static const meetingDetails = '/meeting/details';
  static const meetingConnect = '/meeting/connect';
  static const meetingRecord = '/meeting/record';
  // 语言功能
  static const translationMiddleware = '/translationMiddleware'; // 翻译中间层（统一入口）
  static const translation = '/translation'; // 翻译
  static const pictureTranslation = '/picture_translation'; // 图片翻译
  static const textTranslation = '/text_translation'; // 文本翻译
  static const translationHistory = '/translation/history'; // 翻译历史
  static const usageStats = '/usage/stats'; // 用量统计
  static const speechDemo = '/speech_demo'; // 语音演示
  static const translationList = '/translation/List'; // 翻译历史
  // 测试路由（生产环境建议移除）
  static const ttsTest = '/tts_test'; // 文字转语音测试
  static const asrTest = '/asr_test'; // 语音识别测试
  static const azureAsrTest = '/azure_asr_test'; // Azure语音识别
  static const azureTtsTest = '/azure_tts_test'; // Azure文字转语音
  static const volcanoAsrTest = '/volcano_asr_test'; // 火山引擎语音识别
  static const flutterTtsTest = '/flutter_tts_test'; // Flutter TTS测试
  static const flutterAsrTest = '/flutter_asr_test'; // Flutter ASR测试
  static const jieliTest = '/jieli_test'; // 杰理芯片测试
  static const opusTest = '/opus_test'; // Opus编码测试
  static const logExport = '/log_export'; // 日志导出
  static const bleTest = '/ble_test'; // 蓝牙测试
  static const speechTest = '/speech_test'; // 综合语音测试

  // 支持服务
  static const feedback = '/feedback'; // 用户反馈
  static const agent = '/agent'; // 在线客服
  static const navigation = '/navigation'; // 实时导航

  // 音乐相关
  static const musicPlaylist = '/music/playlist'; // 音乐播放列表

  // 实时语音对话
  static const realtime = '/realtime';

  // 移动精灵
  static const mobileElf = '/mobile_elf';

  // 设备管理
  static const devices = '/devices';

  // ble设备管理
  static const ble = '/ble';
  // ble设备管理
  static const qqmusic = '/qqmusic';

  // 支付相关
  static const payment = '/payment'; // 支付测试页面

  //商品购买页面
  static const goodsvip = '/goodsvip'; //vip商品页面
  static const goodstrans = '/goodstrans'; //翻译商品页面
  static const goodsmeet = '/goodsmeet'; //会议商品页面
  static const goodsai = '/goodsai'; //ai商品页面
}
