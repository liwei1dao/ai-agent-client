package com.aiagent.agent_runtime

import android.content.*
import android.os.IBinder
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import org.json.JSONObject

/**
 * AgentRuntimePlugin — Flutter Plugin 入口
 *
 * 命令通道（Flutter→Native）：接收 startSession / stopSession / sendText / interrupt / setInputMode
 * 事件通道（Native→Flutter）：推送 STT/LLM/TTS 事件和状态变更
 *
 * Pigeon 生成代码就绪后，MethodChannel 手动分发可替换为 Pigeon 自动绑定。
 */
class AgentRuntimePlugin : FlutterPlugin, AgentEventSink {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSinkStream: EventChannel.EventSink? = null

    private var service: AgentRuntimeService? = null
    private var isBound = false
    private lateinit var context: Context

    private val mainScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    // ─────────────────────────────────────────────────
    // FlutterPlugin 生命周期
    // ─────────────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext

        methodChannel = MethodChannel(binding.binaryMessenger, "agent_runtime/commands")
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startSession" -> {
                    val config = call.arguments<Map<*, *>>()!!.toAgentSessionConfig()
                    startServiceIfNeeded()
                    service?.startSession(config)
                    result.success(null)
                }
                "stopSession" -> {
                    service?.stopSession(call.argument("sessionId")!!)
                    result.success(null)
                }
                "sendText" -> {
                    service?.sendText(
                        call.argument("sessionId")!!,
                        call.argument("requestId")!!,
                        call.argument("text")!!,
                    )
                    result.success(null)
                }
                "interrupt" -> {
                    service?.interrupt(call.argument("sessionId")!!)
                    result.success(null)
                }
                "setInputMode" -> {
                    service?.setInputMode(
                        call.argument("sessionId")!!,
                        call.argument("mode")!!,
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        eventChannel = EventChannel(binding.binaryMessenger, "agent_runtime/events")
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSinkStream = events
            }
            override fun onCancel(arguments: Any?) {
                eventSinkStream = null
            }
        })

        bindService()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        if (isBound) context.unbindService(serviceConnection)
        mainScope.cancel()
    }

    // ─────────────────────────────────────────────────
    // AgentEventSink 实现（Native→Flutter 事件推送）
    // ─────────────────────────────────────────────────

    override fun onSttEvent(event: SttEventData) {
        pushEvent(mapOf(
            "type" to "stt",
            "sessionId" to event.sessionId,
            "requestId" to event.requestId,
            "kind" to event.kind,
            "text" to event.text,
            "errorCode" to event.errorCode,
            "errorMessage" to event.errorMessage,
        ))
    }

    override fun onLlmEvent(event: LlmEventData) {
        pushEvent(mapOf(
            "type" to "llm",
            "sessionId" to event.sessionId,
            "requestId" to event.requestId,
            "kind" to event.kind,
            "textDelta" to event.textDelta,
            "thinkingDelta" to event.thinkingDelta,
            "toolCallId" to event.toolCallId,
            "toolName" to event.toolName,
            "toolArgumentsDelta" to event.toolArgumentsDelta,
            "toolResult" to event.toolResult,
            "fullText" to event.fullText,
            "errorCode" to event.errorCode,
            "errorMessage" to event.errorMessage,
        ))
    }

    override fun onTtsEvent(event: TtsEventData) {
        pushEvent(mapOf(
            "type" to "tts",
            "sessionId" to event.sessionId,
            "requestId" to event.requestId,
            "kind" to event.kind,
            "progressMs" to event.progressMs,
            "durationMs" to event.durationMs,
            "errorCode" to event.errorCode,
            "errorMessage" to event.errorMessage,
        ))
    }

    override fun onStateChanged(sessionId: String, state: String, requestId: String?) {
        pushEvent(mapOf(
            "type" to "stateChanged",
            "sessionId" to sessionId,
            "state" to state,
            "requestId" to requestId,
        ))
    }

    override fun onError(sessionId: String, errorCode: String, message: String, requestId: String?) {
        pushEvent(mapOf(
            "type" to "error",
            "sessionId" to sessionId,
            "errorCode" to errorCode,
            "message" to message,
            "requestId" to requestId,
        ))
    }

    private fun pushEvent(data: Map<String, Any?>) {
        mainScope.launch {
            eventSinkStream?.success(data)
        }
    }

    // ─────────────────────────────────────────────────
    // Service 绑定
    // ─────────────────────────────────────────────────

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            service = (binder as AgentRuntimeService.LocalBinder).getService()
            service?.eventSink = this@AgentRuntimePlugin
            isBound = true
        }
        override fun onServiceDisconnected(name: ComponentName?) {
            service = null
            isBound = false
        }
    }

    private fun startServiceIfNeeded() {
        val intent = Intent(context, AgentRuntimeService::class.java)
        context.startForegroundService(intent)
        if (!isBound) bindService()
    }

    private fun bindService() {
        val intent = Intent(context, AgentRuntimeService::class.java)
        context.bindService(intent, serviceConnection, Context.BIND_AUTO_CREATE)
    }
}

// ── 扩展函数：Map → AgentSessionConfig ────────────────────────────────────

private fun Map<*, *>.toAgentSessionConfig() = AgentSessionConfig(
    sessionId = this["sessionId"] as String,
    agentId = this["agentId"] as String,
    inputMode = this["inputMode"] as String,
    sttPluginName = this["sttPluginName"] as String,
    ttsPluginName = this["ttsPluginName"] as String,
    llmPluginName = this["llmPluginName"] as String,
    stsPluginName = this["stsPluginName"] as? String,
    sttConfigJson = this["sttConfigJson"] as String,
    ttsConfigJson = this["ttsConfigJson"] as String,
    llmConfigJson = this["llmConfigJson"] as String,
    stsConfigJson = this["stsConfigJson"] as? String,
)
