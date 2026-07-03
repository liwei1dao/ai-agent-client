package com.aiagent.assistant_server

import android.content.Context
import android.util.Log
import kotlinx.coroutines.*

/**
 * AI 助理场景的总编排器（进程内单例）。
 *
 * 互斥：[active] 至多一个会话；新 start 调用时若已有 active 则抛 `assistant.session_busy`。
 */
internal object AssistantServerCore {

    private const val TAG = "AssistantServerCore"

    @Volatile private var active: AssistantSession? = null
    @Volatile private var emit: ((Map<String, Any?>) -> Unit)? = null

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** 由 Plugin 在 onAttached 时注入；EventChannel 转发器。 */
    fun bindEmitter(emitter: (Map<String, Any?>) -> Unit) {
        this.emit = emitter
    }

    fun unbindEmitter() {
        this.emit = null
    }

    fun activeSessionId(): String? = active?.sessionId

    /**
     * 启动 AI 助理会话。返回 sessionId。
     * 失败 → 抛 IllegalStateException + emit error/sessionState=error。
     */
    fun startAssistant(
        sessionId: String,
        request: AssistantRequest,
        context: Context,
    ): String {
        synchronized(this) {
            active?.let {
                throw IllegalStateException("assistant.session_busy: another session ${it.sessionId} is active")
            }
            val emitter: (Map<String, Any?>) -> Unit = emit ?: { evt ->
                Log.w(TAG, "no emitter bound; event dropped: $evt")
            }
            val session = AssistantSession(sessionId, context, request, emitter)
            active = session

            emitter(AssistantEvents.sessionState(sessionId, "starting"))
            scope.launch {
                try {
                    session.start()
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    Log.e(TAG, "session start failed: ${e.message}", e)
                    val msg = e.message ?: e::class.java.simpleName
                    val code = msg.substringBefore(":").trim().takeIf {
                        it.startsWith("assistant.")
                    } ?: "assistant.start_failed"
                    session.markError(code, msg)
                    if (active === session) active = null
                }
            }
            return sessionId
        }
    }

    /**
     * 停止当前 active session。无 active 时 no-op。
     *
     * 立即把 [active] 置 null（避免重复触发 / 占位竞态），把实际的 [AssistantSession.stop]
     * 拉到 IO scope 跑：里面会 release agent runner，串行化释放在主线程上会触发 ANR。
     */
    fun stopActive() {
        val target = synchronized(this) {
            val s = active ?: return
            active = null
            s
        }
        scope.launch { runCatching { target.stop() } }
    }
}
