import Foundation

/// TtsPipelineNode — iOS TTS 管线节点，推送 7 种 TTS 事件
class TtsPipelineNode {
    let sessionId: String
    let config: AgentSessionConfig
    weak var eventSink: AgentEventSink?

    init(sessionId: String, config: AgentSessionConfig, eventSink: AgentEventSink) {
        self.sessionId = sessionId
        self.config = config
        self.eventSink = eventSink
    }

    func speak(requestId: String, text: String) async {
        guard !Task.isCancelled else { return }
        pushEvent(TtsEventData(sessionId: sessionId, requestId: requestId, kind: "synthesisStart"))

        // TODO: 调用 TTS 插件合成
        // let audioData = try await ttsPlugin.synthesize(text)

        guard !Task.isCancelled else {
            pushEvent(TtsEventData(sessionId: sessionId, requestId: requestId, kind: "playbackInterrupted"))
            return
        }

        pushEvent(TtsEventData(sessionId: sessionId, requestId: requestId, kind: "synthesisReady"))
        pushEvent(TtsEventData(sessionId: sessionId, requestId: requestId, kind: "playbackStart"))

        // TODO: 播放并推送 playbackProgress
        // await audioPlayer.play(audioData) { progressMs, durationMs in
        //     guard !Task.isCancelled else { return }
        //     pushEvent(TtsEventData(..., kind: "playbackProgress", progressMs: progressMs, durationMs: durationMs))
        // }

        if Task.isCancelled {
            pushEvent(TtsEventData(sessionId: sessionId, requestId: requestId, kind: "playbackInterrupted"))
        } else {
            pushEvent(TtsEventData(sessionId: sessionId, requestId: requestId, kind: "playbackDone"))
        }
    }

    private func pushEvent(_ event: TtsEventData) {
        eventSink?.onTtsEvent(event)
    }
}
