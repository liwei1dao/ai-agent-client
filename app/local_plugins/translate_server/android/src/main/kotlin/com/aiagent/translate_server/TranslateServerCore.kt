package com.aiagent.translate_server

import android.content.Context
import android.util.Log
import kotlinx.coroutines.*

/**
 * 复合翻译场景的总编排器（进程内单例）。
 *
 * 三种业务**互斥**：通话翻译 / 面对面翻译 / 音视频翻译，[active] 至多一个。
 * 当前只落地通话翻译；其它两种 stub。
 */
internal object TranslateServerCore {

    private const val TAG = "TranslateServerCore"

    @Volatile private var active: CallTranslationSession? = null
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
     * 启动通话翻译。返回 sessionId。
     * 失败 → 抛 IllegalStateException + emit error/sessionState=error。
     */
    fun startCallTranslation(
        sessionId: String,
        request: CallTranslationRequest,
        context: Context,
    ): String {
        synchronized(this) {
            active?.let {
                throw IllegalStateException("translate.session_busy: another session ${it.sessionId} is active")
            }
            val emitter: (Map<String, Any?>) -> Unit = emit ?: { evt ->
                Log.w(TAG, "no emitter bound; event dropped: $evt")
            }
            val session = CallTranslationSession(sessionId, context, request, emitter)
            active = session

            emitter(TranslateEvents.sessionState(sessionId, "starting"))
            scope.launch {
                try {
                    session.start()
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    Log.e(TAG, "session start failed: ${e.message}", e)
                    val msg = e.message ?: e::class.java.simpleName
                    val code = msg.substringBefore(":").trim().takeIf {
                        it.startsWith("translate.")
                    } ?: "translate.start_failed"
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
     * 立即把 [active] 置 null（避免重复触发 / 占位竞态），把实际的 [CallTranslationSession.stop]
     * 拉到 IO scope 跑：里面会 release Azure SDK 的 recognizer / synthesizer，这些是阻塞调用，
     * 串行化两个 agent × stt+tts 共 4 路释放在主线程上会触发 ANR。
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
