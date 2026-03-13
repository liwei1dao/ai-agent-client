import Foundation

/// VadEngine — iOS 静音检测引擎
class VadEngine {
    let sessionId: String
    weak var eventSink: AgentEventSink?

    private let speechThresholdDb: Float
    private let silenceDurationMs: TimeInterval
    private var isSpeaking = false
    private var lastSpeechTime = Date.distantPast

    init(
        sessionId: String,
        eventSink: AgentEventSink,
        speechThresholdDb: Float = -40,
        silenceDurationMs: TimeInterval = 0.8
    ) {
        self.sessionId = sessionId
        self.eventSink = eventSink
        self.speechThresholdDb = speechThresholdDb
        self.silenceDurationMs = silenceDurationMs
    }

    /// 处理一帧 PCM 音频（Int16 数据）
    func processFrame(_ pcmData: [Int16], sttNode: SttPipelineNode) {
        let rms = calculateRms(pcmData)
        guard rms > 0 else { return }
        let db = 20 * log10(rms)

        if db > speechThresholdDb {
            lastSpeechTime = Date()
            if !isSpeaking {
                isSpeaking = true
                sttNode.onSttRawEvent(kind: "vadSpeechStart", text: nil, isFinal: false)
            }
        } else {
            if isSpeaking && Date().timeIntervalSince(lastSpeechTime) > silenceDurationMs {
                isSpeaking = false
                sttNode.onSttRawEvent(kind: "vadSpeechEnd", text: nil, isFinal: false)
            }
        }
    }

    private func calculateRms(_ samples: [Int16]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
        return Float(sqrt(sum / Double(samples.count)))
    }
}
