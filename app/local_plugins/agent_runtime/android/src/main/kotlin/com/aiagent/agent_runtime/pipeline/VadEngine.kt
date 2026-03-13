package com.aiagent.agent_runtime.pipeline

import com.aiagent.agent_runtime.*

/**
 * VadEngine — 静音检测引擎
 *
 * 检测麦克风音频帧中的语音活动：
 *   - 超过 speechThresholdDb 时触发 vadSpeechStart
 *   - 连续 silenceDurationMs 静音后触发 vadSpeechEnd（驱动 STT 识别）
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
     * @param sttNode 用于触发识别
     */
    fun processFrame(pcmFrame: ShortArray, sttNode: SttPipelineNode) {
        val rms = calculateRms(pcmFrame)
        val db = 20 * Math.log10(rms.toDouble()).toFloat()

        if (db > speechThresholdDb) {
            lastSpeechTime = System.currentTimeMillis()
            if (!isSpeaking) {
                isSpeaking = true
                sttNode.onSttRawEvent("vadSpeechStart", null, false)
            }
        } else {
            if (isSpeaking && (System.currentTimeMillis() - lastSpeechTime) > silenceDurationMs) {
                isSpeaking = false
                sttNode.onSttRawEvent("vadSpeechEnd", null, false)
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
