package com.aiagent.agents_server

import android.app.*
import android.content.Intent
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.aiagent.plugin_interface.*

/**
 * AgentsServerService — Agent 容器前台服务
 *
 * 职责：
 * 1. 持有所有活跃 NativeAgent 实例的生命周期（创建/停止/删除）
 * 2. 实现 AgentEventSink，接收 Agent 事件
 * 3. 通过 eventCallback 将事件转发给 Plugin 层（→ EventChannel → Flutter）
 * 4. 前台服务保活 + 通知栏
 *
 * Plugin 层只做 MethodChannel 调度，将命令委托到此 Service。
 */
class AgentsServerService : Service(), AgentEventSink {

    companion object {
        private const val TAG = "AgentsServerService"
        private const val NOTIFICATION_ID = 1001
    }

    inner class LocalBinder : Binder() {
        fun getService(): AgentsServerService = this@AgentsServerService
    }

    private val binder = LocalBinder()

    /** 活跃 Agent 实例: agentId → NativeAgent */
    private val agents = mutableMapOf<String, NativeAgent>()

    /** Plugin 层设置的事件回调（转发到 EventChannel） */
    var eventCallback: ((Map<String, Any?>) -> Unit)? = null

    // ─────────────────────────────────────────────────
    // Service 生命周期
    // ─────────────────────────────────────────────────

    override fun onBind(intent: Intent): IBinder = binder

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY

    override fun onDestroy() {
        agents.values.forEach { it.release() }
        agents.clear()
        eventCallback = null
        super.onDestroy()
    }

    // ─────────────────────────────────────────────────
    // 前台服务
    // ─────────────────────────────────────────────────

    /** Promote to foreground with MICROPHONE type (required for AudioRecord on Android 14+) */
    fun promoteToForeground() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                buildNotification(),
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
            )
        } else {
            startForeground(NOTIFICATION_ID, buildNotification())
        }
    }

    private fun buildNotification(): Notification {
        val channelId = "agents_server"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "AI Agent",
                NotificationManager.IMPORTANCE_LOW,
            )
            getSystemService(NotificationManager::class.java)
                ?.createNotificationChannel(channel)
        }
        return NotificationCompat.Builder(this, channelId)
            .setContentTitle("AI Agent 运行中")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setOngoing(true)
            .build()
    }

    // ─────────────────────────────────────────────────
    // Agent 生命周期管理
    // ─────────────────────────────────────────────────

    fun createAgent(agentType: String, config: NativeAgentConfig) {
        val agentId = config.agentId
        if (agents.containsKey(agentId)) {
            Log.w(TAG, "Agent already exists: $agentId, releasing old one")
            agents.remove(agentId)?.release()
        }

        try {
            promoteToForeground()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to promote to foreground: ${e.message}", e)
        }

        try {
            val agent = NativeAgentRegistry.create(agentType)
            agent.initialize(config, this, applicationContext)
            agents[agentId] = agent
            Log.d(TAG, "Created agent: type=$agentType id=$agentId (total=${agents.size})")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create agent: ${e.message}", e)
            onError(agentId, "create_error", e.message ?: "Unknown error", null)
        }
    }

    fun stopAgent(agentId: String) {
        agents.remove(agentId)?.release()
        Log.d(TAG, "Stopped agent: $agentId (remaining=${agents.size})")
        if (agents.isEmpty()) {
            stopSelf()
        }
    }

    fun deleteAgent(agentId: String) {
        stopAgent(agentId)
    }

    fun getAgent(agentId: String): NativeAgent? = agents[agentId]

    fun releaseAll() {
        agents.values.forEach { it.release() }
        agents.clear()
    }

    // ─────────────────────────────────────────────────
    // AgentEventSink 实现（Agent → eventCallback → Plugin → Flutter）
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

    override fun onConnectionStateChanged(sessionId: String, state: String, errorMessage: String?) {
        pushEvent(mapOf(
            "type" to "connectionState",
            "sessionId" to sessionId,
            "state" to state,
            "errorMessage" to errorMessage,
        ))
    }

    private fun pushEvent(data: Map<String, Any?>) {
        eventCallback?.invoke(data)
    }
}
