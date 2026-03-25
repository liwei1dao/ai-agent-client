package com.aiagent.agents_server

import android.content.*
import android.os.IBinder
import android.util.Log
import com.aiagent.plugin_interface.*
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

/**
 * AgentsServerPlugin — Agent 容器 Flutter 插件
 *
 * 职责：
 * 1. 管理多个 NativeAgent 实例的生命周期（创建/停止/删除）
 * 2. 路由 Flutter 命令到对应 Agent（sendText/setInputMode/interrupt...）
 * 3. 汇聚所有 Agent 事件 → EventChannel → Flutter UI
 * 4. 管理 ForegroundService 保活
 *
 * 命令通道：agents_server/commands
 * 事件通道：agents_server/events
 */
class AgentsServerPlugin : FlutterPlugin, AgentEventSink {

    companion object {
        private const val TAG = "AgentsServerPlugin"
    }

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSinkStream: EventChannel.EventSink? = null

    private val mainScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private lateinit var context: Context

    /** 活跃 Agent 实例: agentId → NativeAgent */
    private val agents = mutableMapOf<String, NativeAgent>()

    // ForegroundService
    private var service: AgentsServerService? = null
    private var isBound = false

    // ─────────────────────────────────────────────────
    // FlutterPlugin 生命周期
    // ─────────────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext

        methodChannel = MethodChannel(binding.binaryMessenger, "agents_server/commands")
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "createAgent" -> {
                    val config = NativeAgentConfig.fromMap(call.arguments<Map<*, *>>()!!)
                    val agentType = call.argument<String>("agentType")!!
                    createAgent(agentType, config)
                    result.success(null)
                }
                "stopAgent" -> {
                    stopAgent(call.argument<String>("agentId")!!)
                    result.success(null)
                }
                "deleteAgent" -> {
                    deleteAgent(call.argument<String>("agentId")!!)
                    result.success(null)
                }
                "sendText" -> {
                    val agentId = call.argument<String>("agentId")!!
                    agents[agentId]?.sendText(
                        call.argument<String>("requestId")!!,
                        call.argument<String>("text")!!,
                    )
                    result.success(null)
                }
                "setInputMode" -> {
                    val agentId = call.argument<String>("agentId")!!
                    agents[agentId]?.setInputMode(call.argument<String>("mode")!!)
                    result.success(null)
                }
                "startListening" -> {
                    agents[call.argument<String>("agentId")!!]?.startListening()
                    result.success(null)
                }
                "stopListening" -> {
                    agents[call.argument<String>("agentId")!!]?.stopListening()
                    result.success(null)
                }
                "interrupt" -> {
                    agents[call.argument<String>("agentId")!!]?.interrupt()
                    result.success(null)
                }
                "notifyAppForeground" -> {
                    // Optional: app lifecycle notification
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        eventChannel = EventChannel(binding.binaryMessenger, "agents_server/events")
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
        agents.values.forEach { it.release() }
        agents.clear()
        if (isBound) context.unbindService(serviceConnection)
        mainScope.cancel()
    }

    // ─────────────────────────────────────────────────
    // Agent 生命周期管理
    // ─────────────────────────────────────────────────

    private fun createAgent(agentType: String, config: NativeAgentConfig) {
        val agentId = config.agentId
        if (agents.containsKey(agentId)) {
            Log.w(TAG, "Agent already exists: $agentId, releasing old one")
            agents.remove(agentId)?.release()
        }

        // Ensure ForegroundService is running
        startServiceIfNeeded()
        service?.promoteToForeground()

        try {
            val agent = NativeAgentRegistry.create(agentType)
            agent.initialize(config, this, context)
            agents[agentId] = agent
            Log.d(TAG, "Created agent: type=$agentType id=$agentId (total=${agents.size})")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create agent: ${e.message}")
            onError(agentId, "create_error", e.message ?: "Unknown error", null)
        }
    }

    private fun stopAgent(agentId: String) {
        agents.remove(agentId)?.release()
        Log.d(TAG, "Stopped agent: $agentId (remaining=${agents.size})")
        if (agents.isEmpty()) {
            service?.stopSelf()
        }
    }

    private fun deleteAgent(agentId: String) {
        stopAgent(agentId)
    }

    // ─────────────────────────────────────────────────
    // AgentEventSink 实现（Agent → EventChannel → Flutter）
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
    // ForegroundService 绑定
    // ─────────────────────────────────────────────────

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            service = (binder as AgentsServerService.LocalBinder).getService()
            isBound = true
        }
        override fun onServiceDisconnected(name: ComponentName?) {
            service = null
            isBound = false
        }
    }

    private fun startServiceIfNeeded() {
        val intent = Intent(context, AgentsServerService::class.java)
        context.startForegroundService(intent)
        if (!isBound) bindService()
    }

    private fun bindService() {
        val intent = Intent(context, AgentsServerService::class.java)
        context.bindService(intent, serviceConnection, Context.BIND_AUTO_CREATE)
    }
}
