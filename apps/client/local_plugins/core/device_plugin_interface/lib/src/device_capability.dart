/// 厂商插件声明自身支持哪些能力。
///
/// 业务层据此显示/隐藏 UI（OTA 按钮、翻译模式选择等），
/// **禁止**写厂商分支判断。
enum DeviceCapability {
  /// 扫描发现设备（必备）
  scan,

  /// 建立连接（必备）
  connect,

  /// 设备配对/绑定状态查询
  bond,

  /// 读电量
  battery,

  /// 读 RSSI
  rssi,

  /// OTA 固件升级
  ota,

  /// 均衡器（EQ）调参
  eq,

  /// 主动降噪 / 通透模式（ANC/Transparency）
  anc,

  /// 按键自定义映射
  keyMapping,

  /// 佩戴检测事件
  wearDetection,

  /// 设备 → app 麦克风上行（音频通道在 native 内部维护，不直接暴露给 Flutter）
  micUplink,

  /// app → 设备扬声器下行（音频通道在 native 内部维护）
  speakerDownlink,

  /// 设备本地唤醒（PTT 键 / 语音唤醒），派发 [DeviceWakeEvent]
  wakeWord,

  /// 设备端通话翻译（设备自己处理混音、回放，app 侧只下发开关与目标语言）
  onDeviceCallTranslation,

  /// 设备端面对面翻译（同上）
  onDeviceFaceToFaceTranslation,

  /// 设备端录音翻译
  onDeviceRecordingTranslation,

  /// 自定义 RCSP / 私有协议命令（[DeviceSession.invokeFeature] 可用）
  customCommand,
}
