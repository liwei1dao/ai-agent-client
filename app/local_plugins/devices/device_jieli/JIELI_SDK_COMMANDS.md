# 杰理 RCSP SDK 指令 / 常量参考

> **来源**：`android/libs/jl_bluetooth_rcsp_V4.2.0_beta2_40214_20251224.aar` 中
> `com.jieli.bluetooth.constant.Command` 等 class 的 `javap -p -constants` 反编译结果。
> **生成时间**：2026-05-07
> **用途**：核对项目里硬编码的 cmd / opcode / 模式 ID 是否与 SDK 内部定义一致，避免猜测。

---

## 一、RCSP CMD opcode（`com.jieli.bluetooth.constant.Command`）

按 opcode 升序排列，**斜体** = 项目内已被 Kotlin 代码直接调用或回调命中。

| opcode (10) | opcode (16) | 常量名 | 用途速记 |
|---:|---:|---|---|
| 1   | 0x01 | CMD_DATA | 通用数据 |
| 2   | 0x02 | CMD_GET_TARGET_FEATURE_MAP | 拉取设备能力位图 |
| 3   | 0x03 | CMD_GET_TARGET_INFO | 拉取设备基础信息 |
| **4** | **0x04** | ***CMD_RECEIVE_SPEECH_START*** | **耳机语音助手按键唤醒：开始上推语音** |
| **5** | **0x05** | ***CMD_RECEIVE_SPEECH_STOP*** | **耳机语音助手按键松开：停止上推** |
| 6   | 0x06 | CMD_DISCONNECT_CLASSIC_BLUETOOTH | 断开经典蓝牙 |
| 7   | 0x07 | CMD_GET_SYS_INFO | 取系统信息 |
| 8   | 0x08 | CMD_SET_SYS_INFO | 设系统信息 |
| 9   | 0x09 | CMD_SYS_INFO_AUTO_UPDATE | 系统信息自动同步 |
| 10  | 0x0A | CMD_PHONE_CALL_REQUEST | 通话相关请求 |
| 11  | 0x0B | CMD_SWITCH_DEVICE_REQUEST | 多机切换请求 |
| 12  | 0x0C | CMD_START_FILE_BROWSE | 开始文件浏览 |
| 13  | 0x0D | CMD_STOP_FILE_BROWSE | 结束文件浏览 |
| 14  | 0x0E | CMD_FUNCTION | 功能控制（按键映射等） |
| 15  | 0x0F | CMD_LRC_GET_START | 开始拉取歌词 |
| 16  | 0x10 | CMD_LRC_GET_STOP | 停止拉取歌词 |
| 17  | 0x11 | CMD_LRC_PUSH_START_TTS | 推送 TTS 歌词 |
| 18  | 0x12 | CMD_START_PERIPHERALS_SCAN | 设备代扫外设开始 |
| 19  | 0x13 | CMD_UPDATE_PERIPHERALS_RESULT | 代扫结果上报 |
| 20  | 0x14 | CMD_STOP_PERIPHERALS_SCAN | 代扫结束 |
| 22  | 0x16 | CMD_START_FILE_TRANSFER | 文件传输开始 |
| 23  | 0x17 | CMD_STOP_FILE_TRANSFER | 文件传输结束 |
| 24  | 0x18 | CMD_NOTIFY_FILE_TRANSFER_OP | 文件传输操作通知 |
| 25  | 0x19 | CMD_SEARCH_DEVICE | 搜索设备 |
| 26  | 0x1A | CMD_EXTERNAL_FLASH_IO_CTRL | 外部 Flash IO 控制 |
| 27  | 0x1B | CMD_START_LARGE_FILE_TRANSFER | 大文件传输开始 |
| 28  | 0x1C | CMD_STOP_LARGE_FILE_TRANSFER | 大文件传输结束 |
| 29  | 0x1D | CMD_LARGE_FILE_TRANSFER_OP | 大文件传输操作 |
| 30  | 0x1E | CMD_CANCEL_LARGE_FILE_TRANSFER | 取消大文件传输 |
| 31  | 0x1F | CMD_FILE_BROWSE_DELETE | 文件浏览删除 |
| 32  | 0x20 | CMD_LARGE_FILE_TRANSFER_GET_NAME | 取大文件名 |
| 33  | 0x21 | CMD_NOTIFY_PREPARE_ENV | 准备环境通知 |
| 34  | 0x22 | CMD_FORMAT_DEVICE | 设备格式化 |
| 35  | 0x23 | CMD_DELETE_FILE_BY_NAME | 按名删文件 |
| 36  | 0x24 | CMD_READ_FILE_FROM_DEVICE | 从设备读文件 |
| 37  | 0x25 | CMD_RTC_EXPAND | RTC 扩展 |
| 38  | 0x26 | CMD_BATCH | 批量命令 |
| 39  | 0x27 | CMD_DEV_PARAM_EXTEND | 设备参数扩展 |
| 40  | 0x28 | CMD_SMALL_FILE_TRANSFER | 小文件传输 |
| 41  | 0x29 | CMD_READ_ERROR_MSG | 读错误信息 |
| 48  | 0x30 | CMD_DATA_TRANSFER | 通用数据传输 |
| 49  | 0x31 | CMD_QUERY_CONNECTED_PHONE_BT_INFO | 查询已连手机蓝牙信息 |
| 51  | 0x33 | CMD_PUBLIC_SETTINGS | 公共设置 |
| **52** | **0x34** | ***CMD_TRANSLATION_MODE*** | **翻译模式控制 + 上下行 PCM 数据通道** |
| 161 | 0xA1 | CMD_PUSH_MESSAGE_TO_DEVICE | APP → 设备消息推送 |
| 192 | 0xC0 | CMD_ADV_SETTINGS | 广告设置 |
| 193 | 0xC1 | CMD_ADV_GET_INFO | 广告信息查询 |
| 194 | 0xC2 | CMD_ADV_DEVICE_NOTIFY | 设备广告通知 |
| 195 | 0xC3 | CMD_ADV_NOTIFY_SETTINGS | 广告通知设置 |
| 196 | 0xC4 | CMD_ADV_DEV_REQUEST_OPERATION | 设备发起的请求 |
| 208 | 0xD0 | CMD_NOTIFY_DEVICE_APP_INFO | 通知设备 APP 信息 |
| 209 | 0xD1 | CMD_SETTINGS_COMMUNICATION_MTU | 协商通讯 MTU |
| **210** | **0xD2** | ***CMD_RECEIVE_SPEECH_CANCEL*** | **取消语音助手会话** |
| 212 | 0xD4 | CMD_GET_DEV_MD5 | 取设备 MD5 |
| 213 | 0xD5 | CMD_GET_LOW_LATENCY_SETTINGS | 低延时模式设置 |
| 214 | 0xD6 | CMD_GET_EXTERNAL_FLASH_MSG | 外部 Flash 信息 |
| 216 | 0xD8 | CMD_SET_DEVICE_STORAGE | 设备存储设置 |
| 217 | 0xD9 | CMD_GET_DEVICE_CONFIG_INFO | 设备配置信息 |
| 225 | 0xE1 | CMD_OTA_GET_DEVICE_UPDATE_FILE_INFO_OFFSET | OTA：取升级文件偏移 |
| 226 | 0xE2 | CMD_OTA_INQUIRE_DEVICE_IF_CAN_UPDATE | OTA：询问可否升级 |
| 227 | 0xE3 | CMD_OTA_ENTER_UPDATE_MODE | OTA：进入升级模式 |
| 228 | 0xE4 | CMD_OTA_EXIT_UPDATE_MODE | OTA：退出升级模式 |
| 229 | 0xE5 | CMD_OTA_SEND_FIRMWARE_UPDATE_BLOCK | OTA：发送固件块 |
| 230 | 0xE6 | CMD_OTA_GET_DEVICE_REFRESH_FIRMWARE_STATUS | OTA：取刷新状态 |
| 231 | 0xE7 | CMD_REBOOT_DEVICE | 重启设备 |
| 232 | 0xE8 | CMD_OTA_NOTIFY_UPDATE_CONTENT_SIZE | OTA：通知升级内容大小 |
| 240 | 0xF0 | CMD_CUSTOM | 厂商自定义 |
| 241 | 0xF1 | CMD_PHONE_NUMBER_PLAY_MODE | 手机号播报模式 |
| 255 | 0xFF | CMD_EXTRA_CUSTOM | 扩展自定义 |

---

## 二、音频通道两条独立通路（关键）

杰理 SDK 上行麦克风音频实际上有两条**互不关联**的命令通路，调用入口和回调机制完全不同：

### 通路 A：原生语音助手（cmd=4 / 5 / 210）
- **类**：`com.jieli.bluetooth.impl.rcsp.record.RecordOpImpl`
- **回调**：`OnRecordStateCallback`（多回调可共存）
- **触发模型**：固件以"耳机硬键唤醒"为前提才会持续上推
  - APP 主动调用 `startRecord()` 通常只能拿到 `RECORD_STATE_START` 回调，
    `RECORD_STATE_WORKING` 帧推送依赖耳机端按键事件 / 厂商定制
- **下行**：**无**。该通路只管上行
- **不抢占 eSCO / A2DP**

### 通路 B：翻译模式（cmd=52）
- **类**：`com.jieli.bluetooth.impl.rcsp.translation.TranslationImpl`
- **接口**：`writeAudioData()` 上下行复用
- **触发模型**：APP 调用 `enterMode()` 后固件**主动**持续上推 PCM
  - `MODE_CALL_TRANSLATION (3)` + `STRATEGY_DEVICE_ALWAYS_RECORDING (1)` → 不依赖通话事件即可拿帧
  - `MODE_CALL_TRANSLATION_WITH_STEREO (6)` → 依赖真实通话事件（SCO_MIX），AI 助理场景**零帧**
- **下行**：通过 `feedTranslatedAudio()` 走 RCSP 注入回耳机
- **会占用 SCO**，与 A2DP 媒体音乐互斥

> 实测结论（ColorOS + 当前耳机型号）：通路 A 的 `startRecord` 仅有 `START` 回调，
> 持续帧不到货。**当前可拿上行 PCM 的唯一稳定通路是 B（cmd=52）+ MODE_CALL_TRANSLATION (3)**。

---

## 三、`TranslationMode` 模式常量

来自 `com.jieli.bluetooth.bean.translation.TranslationMode`：

| 值 | 常量 | 上行 | 下行 | AI 助理可用性 |
|---:|---|:---:|:---:|---|
| 0 | MODE_IDLE | - | - | 关闭 |
| 1 | MODE_RECORD | ✓ | ✗ | 只录音，不能放 TTS |
| 2 | MODE_RECORDING_TRANSLATION | ✓ | ✗ | 只录音 + 字幕 |
| **3** | **MODE_CALL_TRANSLATION** | ✓ | ✓ | **当前唯一全双工可用** |
| 4 | MODE_AUDIO_TRANSLATION | ✓ | ✓ | 音视频文件翻译，需喂文件 PCM |
| 5 | MODE_FACE_TO_FACE_TRANSLATION | ✓ | ✓ | 面对面翻译，依赖双麦阵列 |
| **6** | **MODE_CALL_TRANSLATION_WITH_STEREO** | **✗** | ✓ | **AI 助理场景零帧 → 必须规避** |

> ⚠️ 项目里 [TranslationModeIds](android/src/main/kotlin/com/jielihome/jielihome/feature/translation/TranslationModeHandler.kt) 与 SDK 编号**完全一致**，
> `MODE_CALL_TRANSLATION = 3`、`MODE_CALL_TRANSLATION_WITH_STEREO = 6`。

### RecordingStrategy（`TranslationMode` 内嵌）

| 值 | 常量 | 含义 |
|---:|---|---|
| 0 | STRATEGY_CUSTOM_RECORDING | APP 自定录音节奏 |
| **1** | **STRATEGY_DEVICE_ALWAYS_RECORDING** | **设备持续录音上推（AI 助理场景需用此项）** |
| 2 | STRATEGY_DEVICE_AUTO_RECORDING | 设备 VAD 自动启停 |

---

## 四、`AudioData.source`（cmd=52 上下行 PCM 包的来源标识）

| 值 | 常量 | 含义 |
|---:|---|---|
| -1 | SOURCE_UNKNOWN | 未知 |
| 0  | SOURCE_FILE | 文件喂入 |
| 1  | SOURCE_DEVICE_MIC | 耳机麦 |
| 2  | SOURCE_PHONE_MIC | 手机麦 |
| 3  | SOURCE_E_SCO_UP_LINK | SCO 上行（通话场景） |
| 4  | SOURCE_E_SCO_DOWN_LINK | SCO 下行（通话场景） |
| 5  | SOURCE_M_SBC | mSBC 编码源 |
| 6  | SOURCE_E_SCO_MIX | SCO 上下行混音（mode=6 stereo 用） |

> AI 助理上行帧实际取自 `SOURCE_DEVICE_MIC`（mode=3）；mode=6 等待 `SOURCE_E_SCO_MIX`，
> 没有真实通话时此源不出包，所以零帧。

---

## 五、`RecordParam`（cmd=4 通路的录音参数）

来自 `com.jieli.bluetooth.bean.record.RecordParam`：

### voiceType
| 值 | 常量 |
|---:|---|
| 0 | VOICE_TYPE_PCM |
| 1 | VOICE_TYPE_SPEEX |
| **2** | **VOICE_TYPE_OPUS**（项目当前使用） |

### sampleRate（**单位是 kHz**，注意不是 Hz）
| 值 | 常量 | 实际频率 |
|---:|---|---:|
| 8  | SAMPLE_RATE_8K  | 8000 Hz |
| **16** | **SAMPLE_RATE_16K** | **16000 Hz**（项目当前使用） |

### vadWay
| 值 | 常量 |
|---:|---|
| **0** | **VAD_WAY_DEVICE**（设备端 VAD，项目当前使用） |
| 1 | VAD_WAY_SDK（SDK 软 VAD） |

---

## 六、`RecordState`（cmd=4 通路的回调状态机）

| 字段 | 值 | 常量 | 说明 |
|---|---:|---|---|
| state | 0 | RECORD_STATE_IDLE | 录音结束 / 异常退出 |
| state | 1 | RECORD_STATE_START | 已应答 startRecord，**注意：不代表后续会有数据** |
| state | 2 | RECORD_STATE_WORKING | 数据持续上推中（payload 见 voiceData / voiceDataBlock） |
| reason | 0 | REASON_NORMAL | 正常 |
| reason | 1 | REASON_STOP | 主动 stop |

字段：
- `voiceDataBlock`：分块裸数据
- `voiceData`：单包数据
- `recordParam`：本次录音参数回带
- `message`：异常描述

---

## 七、音频编解码类型（`com.jieli.bluetooth.constant.Constants`）

| 值 | 常量 |
|---:|---|
| 0 | AUDIO_TYPE_PCM |
| 1 | AUDIO_TYPE_SPEEX |
| **2** | **AUDIO_TYPE_OPUS**（项目当前使用） |
| 3 | AUDIO_TYPE_M_SBC |
| 4 | AUDIO_TYPE_JLA_V2 |

---

## 八、项目现状速查表

| 功能 | 入口类 | 走的 cmd | 模式 ID | 备注 |
|---|---|---:|---:|---|
| 翻译 / 通话翻译 | TranslationFeature | 52 | 3 / 6 | 6 在 ColorOS+AI 场景零帧 |
| 录音（独立通路） | RecordOpImpl | 4 / 5 | - | 当前 AI 助理曾尝试此通路，**实测 WORKING 帧不到货** |
| AI 助理 | JieliAssistantPort | 见下文决策 | - | 上行需复用 cmd=52 + mode=3 |

> **AI 助理音频路由结论**：
> - **上行**：必须走 cmd=52 + `MODE_CALL_TRANSLATION (3)` + `STRATEGY_DEVICE_ALWAYS_RECORDING (1)`，
>   规避 mode=6
> - **下行**：APP 端 `AudioTrack` USAGE_MEDIA 直送（系统蓝牙路由 → A2DP），
>   **不走** RCSP `feedTranslatedAudio`，避免 SCO/A2DP 抢通道

---

## 附：如何从 aar 自行核对

```bash
unzip jl_bluetooth_rcsp_*.aar -d /tmp/jl
unzip /tmp/jl/classes.jar -d /tmp/jl/classes
javap -p -constants /tmp/jl/classes/com/jieli/bluetooth/constant/Command.class
javap -p -constants /tmp/jl/classes/com/jieli/bluetooth/bean/record/RecordParam.class
javap -p -constants /tmp/jl/classes/com/jieli/bluetooth/bean/record/RecordState.class
javap -p -constants /tmp/jl/classes/com/jieli/bluetooth/bean/translation/TranslationMode.class
javap -p -constants /tmp/jl/classes/com/jieli/bluetooth/bean/translation/AudioData.class
javap -p -constants /tmp/jl/classes/com/jieli/bluetooth/constant/Constants.class | grep AUDIO_TYPE
```
