package com.aiagent.ast_polychat

import android.content.Context
import android.util.Log
import com.aiagent.plugin_interface.AstCallback
import com.aiagent.plugin_interface.AstRole
import com.aiagent.plugin_interface.NativeAstService
import com.aiagent.plugin_interface.VoitransWebRtcSession
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import org.json.JSONObject
import java.util.concurrent.ThreadLocalRandom

/**
 * PolyChat 平台 AST 服务实现（WebRTC 传输）
 *
 * DataChannel 协议（`trans_original` / `trans_translated`）携带 `done` 标志：
 *   - `done=false` 中间态（累计快照）→ recognizing
 *   - `done=true`  本段定稿       → recognized + recognitionDone(role)
 *
 * 当 source 与 translated 两个角色都 done 后派发 `recognitionEnd`。
 * 用户重新说话（`user_speaking`）会强制 close + endRound 上一回合。
 */
class AstPolychatService(private val context: Context) : NativeAstService {

    companion object {
        private const val TAG = "AstPolychat"
    }

    private lateinit var session: VoitransWebRtcSession
    private var callback: AstCallback? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // ── Recognition round state ──
    private var currentRequestId: String? = null
    private var sourceRoleOpen = false
    private var translatedRoleOpen = false

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
        resetRoundState()
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
                forceEndRound()
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
        forceEndRound()
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
                beginRound(cb, force = true)
                openRole(cb, AstRole.SOURCE)
            }

            "trans_original" -> {
                beginRound(cb)
                openRole(cb, AstRole.SOURCE)
                val text = json.optString("text", "")
                val done = json.optBoolean("done", false)
                if (text.isNotEmpty()) {
                    val rid = currentRequestId ?: return
                    if (done) {
                        cb.onRecognized(AstRole.SOURCE, rid, text)
                        closeRole(cb, AstRole.SOURCE)
                        maybeEndRound(cb)
                    } else {
                        cb.onRecognizing(AstRole.SOURCE, rid, text)
                    }
                }
            }

            "trans_translated" -> {
                beginRound(cb)
                openRole(cb, AstRole.TRANSLATED)
                val text = json.optString("text", "")
                val done = json.optBoolean("done", false)
                if (text.isNotEmpty()) {
                    val rid = currentRequestId ?: return
                    if (done) {
                        cb.onRecognized(AstRole.TRANSLATED, rid, text)
                        closeRole(cb, AstRole.TRANSLATED)
                        maybeEndRound(cb)
                    } else {
                        cb.onRecognizing(AstRole.TRANSLATED, rid, text)
                    }
                }
            }

            "error" -> {
                val message = json.optString("message", "Unknown error")
                val fatal = json.optBoolean("fatal", false)
                if (fatal) {
                    cb.onError("ast.fatal", message)
                } else {
                    cb.onRecognitionError(currentRequestId, null, "ast.error", message)
                }
            }

            "session_state",
            "mcp_tool_call",
            "mcp_tool_result",
            "disconnect_warning",
            "user_transcription",
            "bot_response_start",
            "bot_response",
            "ai_speaking",
            "ai_stopped",
            "ai_response_done" -> {
                // Not surfaced through AstCallback.
            }

            else -> {
                Log.d(TAG, "Unknown event: $type")
            }
        }
    }

    // ── Recognition round state machine ──

    private fun beginRound(cb: AstCallback, force: Boolean = false) {
        if (currentRequestId != null) {
            if (!force) return
            if (sourceRoleOpen) closeRole(cb, AstRole.SOURCE)
            if (translatedRoleOpen) closeRole(cb, AstRole.TRANSLATED)
            endRound(cb)
        }
        currentRequestId = newRequestId()
    }

    private fun openRole(cb: AstCallback, role: AstRole) {
        val rid = currentRequestId ?: return
        when (role) {
            AstRole.SOURCE -> {
                if (!sourceRoleOpen) {
                    sourceRoleOpen = true
                    cb.onRecognitionStart(role, rid)
                }
            }
            AstRole.TRANSLATED -> {
                if (!translatedRoleOpen) {
                    translatedRoleOpen = true
                    cb.onRecognitionStart(role, rid)
                }
            }
        }
    }

    private fun closeRole(cb: AstCallback, role: AstRole) {
        val rid = currentRequestId ?: return
        when (role) {
            AstRole.SOURCE -> {
                if (sourceRoleOpen) {
                    sourceRoleOpen = false
                    cb.onRecognitionDone(role, rid)
                }
            }
            AstRole.TRANSLATED -> {
                if (translatedRoleOpen) {
                    translatedRoleOpen = false
                    cb.onRecognitionDone(role, rid)
                }
            }
        }
    }

    private fun maybeEndRound(cb: AstCallback) {
        if (sourceRoleOpen || translatedRoleOpen) return
        if (currentRequestId == null) return
        endRound(cb)
    }

    private fun endRound(cb: AstCallback) {
        val rid = currentRequestId ?: return
        cb.onRecognitionEnd(rid)
        resetRoundState()
    }

    private fun forceEndRound() {
        val cb = callback ?: run { resetRoundState(); return }
        if (currentRequestId == null) return
        if (sourceRoleOpen) closeRole(cb, AstRole.SOURCE)
        if (translatedRoleOpen) closeRole(cb, AstRole.TRANSLATED)
        endRound(cb)
    }

    private fun resetRoundState() {
        currentRequestId = null
        sourceRoleOpen = false
        translatedRoleOpen = false
    }

    private fun newRequestId(): String {
        val ms = System.currentTimeMillis()
        val rand = ThreadLocalRandom.current().nextInt(1 shl 30)
            .toString(36).padStart(6, '0')
        return "ast_polychat_${ms}_$rand"
    }
}
