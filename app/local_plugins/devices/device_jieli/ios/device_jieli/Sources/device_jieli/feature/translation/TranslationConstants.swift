import Foundation

/// 翻译流逻辑 ID。Dart `TranslationStreams` / Android `TranslationStreams` 一一对应。
public enum TranslationStreams {
    public static let IN_MIC = "in.mic"
    public static let IN_UPLINK = "in.uplink"           // 通话上行：本机用户
    public static let IN_DOWNLINK = "in.downlink"       // 通话下行：对端
    public static let IN_AUDIO_FILE = "in.audioFile"
    public static let IN_STEREO = "in.stereo"           // 双声道交织 PCM：L=本端 / R=对端

    public static let OUT_SPEAKER = "out.speaker"
    public static let OUT_UPLINK = "out.uplink"
    public static let OUT_DOWNLINK = "out.downlink"
    public static let OUT_LOCAL_PLAYBACK = "out.localPlayback"
}

/// 与 SDK `JLTranslateSetModeType` 完全一致；和 Dart `TranslationModeIds` 对齐。
///
/// 注：SDK 的 `JLTranslateSetModeType` 枚举只显式定义到 0x06，`MODE_CALL_RECORD = 7`
/// 对齐 Android `TranslationMode.MODE_CALL_RECORD`（SDK 内部值 7）—— 耳机固件支持，
/// 通过 `JLTranslateSetModeType(rawValue: 7)` 直接下发到设备。
public enum TranslationModeIds {
    public static let MODE_IDLE = 0
    public static let MODE_RECORD = 1
    public static let MODE_RECORDING_TRANSLATION = 2
    public static let MODE_CALL_TRANSLATION = 3
    public static let MODE_AUDIO_TRANSLATION = 4
    public static let MODE_FACE_TO_FACE_TRANSLATION = 5
    public static let MODE_CALL_TRANSLATION_WITH_STEREO = 6
    public static let MODE_CALL_RECORD = 7
}

/// 一帧 PCM 音频规格
public struct AudioFormat {
    public let sampleRate: Int
    public let channels: Int
    public let bitsPerSample: Int
    public init(sampleRate: Int = 16000, channels: Int = 1, bitsPerSample: Int = 16) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitsPerSample = bitsPerSample
    }
}
