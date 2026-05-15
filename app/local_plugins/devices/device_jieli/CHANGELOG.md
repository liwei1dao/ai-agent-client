## 0.0.2

### iOS 端补全 / 与 Android 对齐（参考 `JIELI-IOS-Release`）

#### 框架
- 拷贝 `JIELI-IOS-Release/Libs/` 下全部 `.xcframework` + sample 项目里的 `JLAudioUnitKit.xcframework`（OPUS 编解码所需）到 `ios/Frameworks/`，通过 `vendored_frameworks` 引入。
- `pubspec.yaml` 新增 `ios` 平台条目；`ios/device_jieli.podspec` 配置完成。

#### 与 Android 同名 / 同形态的核心通路（按 user 要求全量对齐）

| 通路 | Android | iOS |
|---|---|---|
| 设备连接 | `ConnectFeature` → `JL_BluetoothManager.connect` + `setUseDeviceAuth(true)` | `ConnectFeature` → `JL_BLEMultiple.connectEntity` + `authEnable=true`；paired 后**自动调 `cmdTargetFeatureResult`** + `cmdGetSystemInfo(.COMMON)` 把 model 拉满，再外抛 `rcspInit` |
| 电量推送 | `OnRcspEventListener.onBatteryChange` → `battery` 事件 | `DeviceInfoEventForwarder` 订阅 `kJL_MANAGER_HEADSET_ADV` / `kJL_MANAGER_SYSTEM_INFO`，合成 `battery` 事件（带 `level/left/right/case` 字段，去重） |
| 通话状态 | `onPhoneCallStatusChange` → `phoneCallStatus` | `DeviceInfoEventForwarder` 订阅 `kJL_MANAGER_CALL_STATUS` |
| 通话翻译 mode=3 | `CallTranslationModeHandler` (uplink/downlink × OPUS 编解码) | `CallTranslationModeHandler` 完整复刻：`OpusStreamDecoder(channels=1, dataSize=40)` 分流 escoUp/escoDown，下行 PCM `OpusStreamEncoder` 编码后 `trWriteAudio(.escoUp/.escoDown)` |
| 通话翻译 mode=6（立体声）| `StereoCallTranslationModeHandler` + `PcmKit.splitStereo16` | `StereoCallTranslationModeHandler` 完整复刻：`OpusStreamDecoder(channels=2, dataSize=80)` → `PcmKit.splitStereo16` → uplink/downlink 两路 |
| MODE_CALL_TRANSLATION + OPUS 自动升级到 stereo | ✅ | ✅（`bypassStereoUpgrade=true` 可禁用，行为与 Android 一致） |
| AI 助理 | `JieliAssistantPort` (MODE_RECORD + STRATEGY_DEVICE_ALWAYS_RECORDING + OPUS) | `AssistantBridge` 复刻：通过 `TranslationSession.acquire` 拿独占所有权，`trStartTranslateMode(.onlyRecord, OPUS, ch=1)` + `recordtype=.byDevice`，`OpusStreamDecoder(channels=1, dataSize=40)` 解出 16k mono PCM → `assistantAudio` |
| 设备录音 | `JieliDeviceRecordPort` (mode=6 stereo + DEVICE_ALWAYS_RECORDING) | `DeviceRecordFeature` 复刻：`trStartTranslateMode(.callTranslateStereo, OPUS, ch=2)` + `recordtype=.byDevice`，`OpusStreamDecoder(channels=2, dataSize=80)` 解出 stereo PCM → `deviceRecordAudio` |
| OTA | 自实现 cmd-level 状态机 | 直接走 `JL_BLEMultiple.otaFunc(...)` 高层 API，结果回调映射到 `otaState` / `otaError` |

#### TranslationSession 互斥模型
iOS SDK 一台设备只有一个 `JLTranslationManager`，与 Android 同样要求"翻译 / 助理 / 设备录音"三选一互斥。新增 [TranslationSession](ios/Classes/core/TranslationSession.swift)：
- 内部持有 `JLTranslationManager` 实例，自身作为 `JLTranslationManagerDelegate`
- 通过 `acquire(owner:)` / `release(owner:)` 协调当前会话所有者
- 所有 SDK 回调（`onReceiveAudioData` / `onModeChange` / `onError` / `onSendAudioQueueOver` / `isOnCalling`）fan-out 到当前 owner

#### 文件清单（`ios/Classes/`）
```
JielihomePlugin.swift                          # Flutter 入口
MethodRouter.swift                             # MethodChannel 路由
EventDispatcher.swift                          # EventChannel 总线
JieliHomeServer.swift                          # 单例 + per-device session

core/TranslationSession.swift                  # 设备级翻译会话所有者协调
audio/OpusStreamCodec.swift                    # JLOpusDecoder/Encoder 包装
audio/PcmKit.swift                             # 16-bit stereo split / interleave

event/BluetoothEventForwarder.swift            # BLE 状态 / 连接通知
event/CustomEventForwarder.swift               # 厂商扩展指令
event/DeviceInfoEventForwarder.swift           # 电量 / 通话 / 系统信息

feature/ScanFeature.swift
feature/ConnectFeature.swift
feature/DeviceInfoFeature.swift
feature/CustomCmdFeature.swift
feature/OtaFeature.swift
feature/TranslationFeature.swift               # 6-mode dispatcher
feature/translation/TranslationConstants.swift
feature/translation/TranslationModeHandler.swift
feature/translation/mode/RecordModeHandler.swift         (mode=1 + RecordingTranslation mode=2)
feature/translation/mode/CallTranslationModeHandler.swift          (mode=3)
feature/translation/mode/StereoCallTranslationModeHandler.swift    (mode=6)
feature/translation/mode/AudioAndFaceModeHandlers.swift            (mode=4 + mode=5)
feature/AssistantBridge.swift
feature/DeviceRecordFeature.swift
feature/SpeechFeature.swift                    # 状态机骨架（详见下方）
```

### 与 Android 实际差异

| 项 | Android | iOS | 影响 |
|---|---|---|---|
| `address` 含义 | BLE MAC | CoreBluetooth identifier (UUID) | iOS 系统对 BLE MAC 永久匿名；上层若用 address 做主键需要做厂商适配 |
| 录音策略 | 三选一：CUSTOM/ALWAYS/AUTO | 二选一：`.byPhone`(=CUSTOM) / `.byDevice`(=ALWAYS) | iOS SDK 不暴露 AUTO（VAD 自动启停），调用 `strategy="auto"` 时回退到 default |
| `versionCode` 字段 | SDK 有 numeric versionCode | SDK 只有 versionFirmware（字符串） | `deviceSnapshot` 里 versionCode 为 null |
| `sendCustomCmd` opCode | SDK 有专门字段 | iOS `JL_CustomManager.cmdCustomData:` 无 opCode 字段 | iOS 实现把 Dart 传入的 opCode 拼到 payload 头部（业务双方约定） |
| `OTA` 状态机 | 插件自实现 cmd 级状态机 | 直接走 SDK 高层 API | Dart `otaStart` 的 `blockSize` / `fileFlag` 参数 iOS 端忽略 |
| `speechStart/Stop`（cmd=4/5 通路） | 完整实现 | 仅状态机外抛 `speechStart/End`，**不拉真实音频** | iOS SDK 4.2 beta 没把 cmd=4/5 通路暴露成公开 Swift API；耳机硬件唤醒的上行帧通过翻译通路接管 |

### 真机验证状态

| 子系统 | 单元自测 | 真机验证 |
|---|---|---|
| 扫描 / 连接 / 断开 | ✅ 编译通过 | ⬜ |
| `battery` / `phoneCallStatus` 推送 | ✅ | ⬜ |
| `deviceSnapshot` / `queryTargetInfo` / `sendCustomCmd` | ✅ | ⬜ |
| OTA | ✅ | ⬜ |
| 通话翻译 mode=3 + OPUS 上下行 | ✅ | ⬜ |
| 通话翻译 mode=6 立体声 | ✅ | ⬜ |
| AI 助理 (MODE_RECORD + byDevice + OPUS) | ✅ | ⬜ |
| 设备录音 (mode=6 + stereo + byDevice + OPUS) | ✅ | ⬜ |

## 0.0.1

* TODO: Describe initial release.
