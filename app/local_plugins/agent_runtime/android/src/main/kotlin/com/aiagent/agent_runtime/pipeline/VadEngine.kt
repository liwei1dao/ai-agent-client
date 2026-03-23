package com.aiagent.agent_runtime.pipeline

import com.aiagent.agent_runtime.*

/**
 * VadEngine — 静音检测引擎（备用，Azure STT 内置 VAD）
 *
 * 当使用 Azure STT SDK 时，SDK 内部已处理语音活动检测（speechStartDetected/speechEndDetected）。
 * 此引擎保留用于将来接入不含 VAD 的 STT 实现。
 */
class VadEngine(
    private val sessionId: String,
    private val eventSink: AgentEventSink,
    private val speechThresholdDb: Float = -40f,
    private val silenceDurationMs: Long = 800L,
) {
    private var isSpeaking = false
    private var lastSpeechTime = 0L

    /**
     * 处理一帧 PCM 音频数据（由录音线程调用）
     * @param pcmFrame 16-bit PCM 数据
     */
    fun processFrame(pcmFrame: ShortArray) {
        val rms = calculateRms(pcmFrame)
        val db = 20 * Math.log10(rms.toDouble()).toFloat()

        if (db > speechThresholdDb) {
            lastSpeechTime = System.currentTimeMillis()
            if (!isSpeaking) {
                isSpeaking = true
                eventSink.onSttEvent(SttEventData(sessionId, requestId = "", kind = "vadSpeechStart"))
            }
        } else {
            if (isSpeaking && (System.currentTimeMillis() - lastSpeechTime) > silenceDurationMs) {
                isSpeaking = false
                eventSink.onSttEvent(SttEventData(sessionId, requestId = "", kind = "vadSpeechEnd"))
            }
        }
    }

    private fun calculateRms(pcm: ShortArray): Float {
        if (pcm.isEmpty()) return 0f
        var sum = 0.0
        for (sample in pcm) sum += sample * sample
        return Math.sqrt(sum / pcm.size).toFloat()
    }

    fun release() {
        isSpeaking = false
    }
}
