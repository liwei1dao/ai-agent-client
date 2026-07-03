import Flutter
import MicrosoftCognitiveServicesSpeech

/**
 * SttAzurePlugin — Azure 语音识别 iOS 实现
 *
 * 推送 7 种 STT 事件（与 Android 完全对称）：
 *   listeningStarted / vadSpeechStart / vadSpeechEnd /
 *   partialResult / finalResult / listeningStopped / error
 */
public class SttAzurePlugin: NSObject, FlutterPlugin {

    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?

    private var recognizer: SPXSpeechRecognizer?
    private var speechConfig: SPXSpeechConfiguration?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = SttAzurePlugin()

        instance.methodChannel = FlutterMethodChannel(
            name: "stt_azure/commands",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(instance, channel: instance.methodChannel!)

        instance.eventChannel = FlutterEventChannel(
            name: "stt_azure/events",
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
            let lang = args["language"] as? String ?? "zh-CN"
            initialize(apiKey: key, region: region, language: lang)
            result(nil)
        case "startListening":
            startListening()
            result(nil)
        case "stopListening":
            stopListening()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // ─────────────────────────────────────────────────
    // MARK: — 实现
    // ─────────────────────────────────────────────────

    private func initialize(apiKey: String, region: String, language: String) {
        recognizer = nil
        speechConfig = nil

        guard let config = try? SPXSpeechConfiguration(subscription: apiKey, region: region) else {
            pushEvent(["kind": "error", "errorCode": "init_failed", "errorMessage": "SPXSpeechConfiguration init error"])
            return
        }
        config.speechRecognitionLanguage = language
        speechConfig = config

        let audioConfig = SPXAudioConfiguration()
        guard let rec = try? SPXSpeechRecognizer(speechConfiguration: config, audioConfiguration: audioConfig) else {
            pushEvent(["kind": "error", "errorCode": "recognizer_init_failed"])
            return
        }

        // Partial result
        rec.addRecognizingEventHandler { [weak self] (_: SPXSpeechRecognizer, e: SPXSpeechRecognitionEventArgs) in
            self?.pushEvent(["kind": "partialResult", "text": e.result.text ?? ""])
        }
        // Final result
        rec.addRecognizedEventHandler { [weak self] (_: SPXSpeechRecognizer, e: SPXSpeechRecognitionEventArgs) in
            if e.result.reason == SPXResultReason.recognizedSpeech {
                self?.pushEvent(["kind": "finalResult", "text": e.result.text ?? ""])
            }
        }
        // Session start
        rec.addSessionStartedEventHandler { [weak self] (_: SPXRecognizer, _: SPXSessionEventArgs) in
            self?.pushEvent(["kind": "listeningStarted"])
        }
        // Session stop
        rec.addSessionStoppedEventHandler { [weak self] (_: SPXRecognizer, _: SPXSessionEventArgs) in
            self?.pushEvent(["kind": "listeningStopped"])
        }
        // VAD speech start
        rec.addSpeechStartDetectedEventHandler { [weak self] (_: SPXRecognizer, _: SPXRecognitionEventArgs) in
            self?.pushEvent(["kind": "vadSpeechStart"])
        }
        // VAD speech end
        rec.addSpeechEndDetectedEventHandler { [weak self] (_: SPXRecognizer, _: SPXRecognitionEventArgs) in
            self?.pushEvent(["kind": "vadSpeechEnd"])
        }
        // Canceled / error
        rec.addCanceledEventHandler { [weak self] (_: SPXRecognizer, e: SPXSpeechRecognitionCanceledEventArgs) in
            if e.reason == SPXCancellationReason.error {
                self?.pushEvent([
                    "kind": "error",
                    "errorCode": "\(e.errorCode)",
                    "errorMessage": e.errorDetails ?? ""
                ])
            }
        }

        recognizer = rec
    }

    private func startListening() {
        guard let rec = recognizer else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            try? rec.startContinuousRecognition()
        }
    }

    private func stopListening() {
        guard let rec = recognizer else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            try? rec.stopContinuousRecognition()
        }
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

extension SttAzurePlugin: FlutterStreamHandler {
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        recognizer = nil
        return nil
    }
}
