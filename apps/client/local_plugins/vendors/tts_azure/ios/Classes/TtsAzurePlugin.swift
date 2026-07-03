import Flutter
import AVFoundation
import MicrosoftCognitiveServicesSpeech

/**
 * TtsAzurePlugin — Azure 语音合成 iOS 实现
 *
 * 推送 7 种 TTS 事件（与 Android 完全对称）：
 *   synthesisStart / synthesisReady / playbackStart /
 *   playbackProgress / playbackDone / playbackInterrupted / error
 */
public class TtsAzurePlugin: NSObject, FlutterPlugin {

    /// 音频输出模式（全局共享）
    enum AudioOutputMode: String {
        case earpiece
        case speaker
        case auto
    }

    static var audioOutputMode: AudioOutputMode = .auto

    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?

    private var synthesizer: SPXSpeechSynthesizer?
    private var currentRequestId = ""

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = TtsAzurePlugin()

        instance.methodChannel = FlutterMethodChannel(
            name: "tts_azure/commands",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(instance, channel: instance.methodChannel!)

        instance.eventChannel = FlutterEventChannel(
            name: "tts_azure/events",
            binaryMessenger: registrar.messenger()
        )
        instance.eventChannel?.setStreamHandler(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "initialize":
            let key = args["apiKey"] as! String
            let region = args["region"] as! String
            let voice = args["voiceName"] as? String ?? "zh-CN-XiaoxiaoNeural"
            initialize(apiKey: key, region: region, voiceName: voice)
            result(nil)
        case "speak":
            let text = args["text"] as! String
            let reqId = args["requestId"] as? String ?? ""
            applyAudioOutputRoute()
            speak(text: text, requestId: reqId)
            result(nil)
        case "stop":
            stop()
            result(nil)
        case "setAudioOutputMode":
            let mode = args["mode"] as? String ?? "auto"
            TtsAzurePlugin.audioOutputMode = AudioOutputMode(rawValue: mode) ?? .auto
            applyAudioOutputRoute()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// 根据当前模式配置 AVAudioSession 输出路由
    private func applyAudioOutputRoute() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, options: [.allowBluetooth, .allowBluetoothA2DP])

            switch TtsAzurePlugin.audioOutputMode {
            case .earpiece:
                try session.overrideOutputAudioPort(.none)
            case .speaker:
                try session.overrideOutputAudioPort(.speaker)
            case .auto:
                // 有耳机走系统路由，无耳机走扬声器
                if isHeadsetConnected() {
                    try session.overrideOutputAudioPort(.none)
                } else {
                    try session.overrideOutputAudioPort(.speaker)
                }
            }
            try session.setActive(true)
        } catch {
            NSLog("TtsAzurePlugin: Failed to configure audio session: \(error)")
        }
    }

    /// 检测是否有耳机连接（有线或蓝牙）
    private func isHeadsetConnected() -> Bool {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        return outputs.contains { port in
            port.portType == .headphones ||
            port.portType == .bluetoothA2DP ||
            port.portType == .bluetoothHFP ||
            port.portType == .bluetoothLE ||
            port.portType == .usbAudio
        }
    }

    // ─────────────────────────────────────────────────
    // MARK: — 实现
    // ─────────────────────────────────────────────────

    private func initialize(apiKey: String, region: String, voiceName: String) {
        synthesizer = nil
        guard let config = try? SPXSpeechConfiguration(subscription: apiKey, region: region) else {
            pushEvent(["kind": "error", "errorCode": "init_failed"])
            return
        }
        config.speechSynthesisVoiceName = voiceName

        let audioConfig = SPXAudioConfiguration()
        guard let synth = try? SPXSpeechSynthesizer(speechConfiguration: config, audioConfiguration: audioConfig) else {
            pushEvent(["kind": "error", "errorCode": "synth_init_failed"])
            return
        }

        // 合成开始
        synth.addSynthesisStartedEventHandler { [weak self] (_: SPXSpeechSynthesizer, _: SPXSpeechSynthesisEventArgs) in
            guard let self = self else { return }
            self.pushEvent(["kind": "synthesisStart", "requestId": self.currentRequestId])
        }
        // 合成中（数据块）
        synth.addSynthesizingEventHandler { [weak self] (_: SPXSpeechSynthesizer, e: SPXSpeechSynthesisEventArgs) in
            guard let self = self else { return }
            let durationMs = Int(e.result.audioDuration / 10_000)
            self.pushEvent([
                "kind": "synthesisReady",
                "requestId": self.currentRequestId,
                "durationMs": durationMs
            ])
        }
        // 合成完成 → 触发播放 start + done
        synth.addSynthesisCompletedEventHandler { [weak self] (_: SPXSpeechSynthesizer, _: SPXSpeechSynthesisEventArgs) in
            guard let self = self else { return }
            self.pushEvent(["kind": "playbackStart", "requestId": self.currentRequestId])
            self.pushEvent(["kind": "playbackDone", "requestId": self.currentRequestId])
        }
        // 取消/错误
        synth.addSynthesisCanceledEventHandler { [weak self] (_: SPXSpeechSynthesizer, e: SPXSpeechSynthesisEventArgs) in
            guard let self = self else { return }
            if let detail = try? SPXSpeechSynthesisCancellationDetails(fromCanceledSynthesisResult: e.result),
               detail.reason == SPXCancellationReason.error {
                self.pushEvent([
                    "kind": "error",
                    "requestId": self.currentRequestId,
                    "errorCode": "\(detail.errorCode)",
                    "errorMessage": detail.errorDetails ?? ""
                ])
            } else {
                self.pushEvent(["kind": "playbackInterrupted", "requestId": self.currentRequestId])
            }
        }

        synthesizer = synth
    }

    private func speak(text: String, requestId: String) {
        currentRequestId = requestId
        pushEvent(["kind": "synthesisStart", "requestId": requestId])
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = try? self?.synthesizer?.speakText(text)
        }
    }

    private func stop() {
        try? synthesizer?.stopSpeaking()
        pushEvent(["kind": "playbackInterrupted", "requestId": currentRequestId])
    }

    private func pushEvent(_ data: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(data)
        }
    }
}

// ─────────────────────────────────────────────────
// MARK: — FlutterStreamHandler
// ─────────────────────────────────────────────────

extension TtsAzurePlugin: FlutterStreamHandler {
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}
