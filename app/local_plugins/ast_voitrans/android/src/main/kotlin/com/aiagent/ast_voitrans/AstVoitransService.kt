package com.aiagent.ast_voitrans

import android.content.Context
import android.util.Log
import com.aiagent.plugin_interface.AstCallback
import com.aiagent.plugin_interface.NativeAstService
import com.aiagent.plugin_interface.VoitransWebRtcSession
import kotlinx.coroutines.*
import org.json.JSONObject

/**
 * VoiTrans 平台 AST 服务实现（WebRTC 传输）
 *
 * 通过 VoitransWebRtcSession 建立 WebRTC 连接，
 * 解析 DataChannel 中的 AST 模式事件并映射到 AstCallback。
 */
class AstVoitransService(private val context: Context) : NativeAstService {

    companion object {
        private const val TAG = "AstVoitrans"
    }

    private lateinit var session: VoitransWebRtcSession
    private var callback: AstCallback? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

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

    override fun connect(callback: AstCallback) {
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
        // WebRTC 模式下打断靠服务端 VAD 检测
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

        when (type) {
            "user_speaking" -> {
                cb.onSpeechStart()
            }

            "trans_original" -> {
                val text = json.optString("text", "")
                if (text.isNotEmpty()) {
                    cb.onSourceSubtitle(text)
                }
            }

            "trans_translated" -> {
                val text = json.optString("text", "")
                if (text.isNotEmpty()) {
                    cb.onTranslatedSubtitle(text)
                }
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

            else -> {
                Log.d(TAG, "Unknown event: $type")
            }
        }
    }
}
