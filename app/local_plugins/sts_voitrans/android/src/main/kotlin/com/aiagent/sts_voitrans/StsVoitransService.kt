package com.aiagent.sts_voitrans

import android.content.Context
import android.util.Log
import com.aiagent.plugin_interface.NativeStsService
import com.aiagent.plugin_interface.StsCallback
import com.aiagent.plugin_interface.VoitransWebRtcSession
import kotlinx.coroutines.*
import org.json.JSONObject

/**
 * VoiTrans 平台 STS 服务实现（WebRTC 传输）
 *
 * 通过 VoitransWebRtcSession 建立 WebRTC 连接，
 * 解析 DataChannel 中的 STS 模式事件并映射到 StsCallback。
 */
class StsVoitransService(private val context: Context) : NativeStsService {

    companion object {
        private const val TAG = "StsVoitrans"
    }

    private lateinit var session: VoitransWebRtcSession
    private var callback: StsCallback? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    /** 累积的 bot 回复文本（逐字 delta 累加，done 时重置） */
    private val botBuffer = StringBuilder()

    override fun initialize(configJson: String, context: Context) {
        val cfg = JSONObject(configJson)
        VoitransWebRtcSession.warmupHttp(cfg.getString("baseUrl"))
        session = VoitransWebRtcSession(context)
        session.initialize(
            baseUrl = cfg.getString("baseUrl"),
            appId = cfg.getString("appId"),
            appSecret = cfg.getString("appSecret"),
            agentId = cfg.getString("agentId"),
        )
        Log.d(TAG, "Initialized: agentId=${cfg.getString("agentId")}")
    }

    override fun connect(callback: StsCallback) {
        this.callback = callback
        session.connect(object : VoitransWebRtcSession.EventListener {
            override fun onConnected() {
                Log.d(TAG, "Connected")
                callback.onConnected()
            }

            override fun onMessage(json: JSONObject) {
                handleDataChannelMessage(json)
            }

            override fun onDisconnected() {
                Log.d(TAG, "Disconnected")
                callback.onDisconnected()
            }

            override fun onError(code: String, message: String) {
                Log.e(TAG, "Error: [$code] $message")
                callback.onError(code, message)
            }
        })
    }

    override fun startAudio() {
        session.startAudio()
    }

    override fun stopAudio() {
        session.stopAudio()
    }

    override fun interrupt() {
        // WebRTC 模式下 AI 语音由远端 audio track 播放，
        // 打断主要靠用户开始说话（user_speaking 事件触发服务端打断）
    }

    override fun release() {
        scope.cancel()
        session.release()
        callback = null
    }

    // ── DataChannel 事件映射 ──

    private fun handleDataChannelMessage(json: JSONObject) {
        val cb = callback ?: return
        val type = json.optString("type", "")
        Log.d(TAG, "DC event: $type → ${json.toString().take(200)}")

        when (type) {
            "user_speaking" -> {
                cb.onSpeechStart()
            }

            "user_transcription" -> {
                val text = json.optString("text", "")
                val done = json.optBoolean("done", false)
                if (done) {
                    cb.onSttFinalResult(text)
                } else {
                    cb.onSttPartialResult(text)
                }
            }

            "bot_response_start" -> {
                botBuffer.clear()
                cb.onStateChanged("llm")
            }

            "bot_response" -> {
                val text = json.optString("text", "")
                val done = json.optBoolean("done", false)
                if (text.isNotEmpty()) {
                    if (done) {
                        // done=true: 服务端发的是完整文本，直接用它覆盖
                        botBuffer.clear()
                        cb.onSentenceDone(text)
                    } else {
                        // done=false: 逐字 delta，累加后发送累积文本（UI 覆盖显示）
                        botBuffer.append(text)
                        cb.onSentenceDone(botBuffer.toString())
                    }
                }
            }

            "ai_response_done" -> {
                cb.onStateChanged("playing")
            }

            "ai_speaking" -> {
                cb.onStateChanged("playing")
            }

            "ai_stopped" -> {
                cb.onStateChanged("idle")
            }

            "session_state" -> {
                val state = json.optString("state", "")
                cb.onStateChanged(state)
            }

            "error" -> {
                val message = json.optString("message", "Unknown error")
                val fatal = json.optBoolean("fatal", false)
                cb.onError(if (fatal) "fatal" else "error", message)
            }

            "disconnect_warning" -> {
                val reason = json.optString("reason", "")
                Log.w(TAG, "Disconnect warning: $reason")
            }

            "mcp_tool_call" -> {
                val funcName = json.optString("function", "")
                Log.d(TAG, "MCP tool call: $funcName")
            }

            "mcp_tool_result" -> {
                val funcName = json.optString("function", "")
                val success = json.optBoolean("success", false)
                Log.d(TAG, "MCP tool result: $funcName success=$success")
            }

            else -> {
                Log.d(TAG, "Unknown event: $type")
            }
        }
    }
}
