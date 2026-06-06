package com.aiagent.agents_server

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import com.aiagent.plugin_interface.*

/**
 * AgentsServerService — Agent 容器服务（前台保活）
 *
 * 职责：
 * 1. 持有所有活跃 NativeAgent 实例的生命周期（创建/停止/删除）
 * 2. 实现 AgentEventSink，接收 Agent 事件
 * 3. 通过 eventCallback 将事件转发给 Plugin 层（→ EventChannel → Flutter）
 * 4. 作为 **started + foreground** 服务运行：有活跃 agent 时升为前台服务，
 *    使整个进程（含 BLE 连接、native agent）在锁屏/切后台/划掉 app 时不被系统回收。
 *
 * Plugin 层只做 MethodChannel 调度，将命令委托到此 Service；
 * createAgent 时由 Plugin 调 startForegroundService 触发 onStartCommand → startForeground。
 */
class AgentsServerService : Service(), AgentEventSink {

    companion object {
        private const val TAG = "AgentsServerService"

        const val ACTION_ENSURE_FOREGROUND = "com.aiagent.agents_server.ENSURE_FOREGROUND"

        private const val CHANNEL_ID = "agents_server_running"
        private const val CHANNEL_NAME = "AI 对话运行中"
        private const val NOTIFICATION_ID = 0x4147 // 'AG'
    }

    /** 是否已处于前台状态，避免重复 startForeground */
    private var isForeground = false

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

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onBind(intent: Intent): IBinder = binder

    /**
     * 由 Plugin 的 startForegroundService(ACTION_ENSURE_FOREGROUND) 触发。
     * 必须在 5s 内调用 startForeground，否则系统抛 ANR；这里立即提升前台。
     * START_STICKY：进程被系统回收后，资源允许时重建 service（intent 为 null）。
     */
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureForeground()
        return START_STICKY
    }

    /**
     * 用户从最近任务划掉 app。只要还有活跃 agent，就保持前台服务运行（不 stopSelf），
     * 让 BLE + native agent 在无 UI 状态下继续工作；没有 agent 时正常退出。
     */
    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.d(TAG, "onTaskRemoved: activeAgents=${agents.size}")
        if (agents.isEmpty()) {
            stopForegroundAndSelf()
        }
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        agents.values.forEach { it.release() }
        agents.clear()
        eventCallback = null
        if (isForeground) {
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
            isForeground = false
        }
        super.onDestroy()
    }

    // ─────────────────────────────────────────────────
    // 前台服务保活
    // ─────────────────────────────────────────────────

    /** 升为前台服务（幂等）。声明 microphone|connectedDevice 类型以覆盖录音 + BLE 设备。 */
    private fun ensureForeground() {
        if (isForeground) return
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
        } else {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
        }
        try {
            ServiceCompat.startForeground(this, NOTIFICATION_ID, buildNotification(), type)
            isForeground = true
            Log.d(TAG, "Promoted to foreground service")
        } catch (e: Exception) {
            // Android 12+ 后台启动前台服务受限（ForegroundServiceStartNotAllowedException）等
            Log.e(TAG, "startForeground failed: ${e.message}", e)
        }
    }

    private fun stopForegroundAndSelf() {
        if (isForeground) {
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
            isForeground = false
        }
        stopSelf()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "保持 AI 对话与设备连接在后台运行"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        // 点击通知回到 app
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pending = launchIntent?.let {
            PendingIntent.getActivity(
                this, 0, it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(applicationInfo.loadLabel(packageManager))
            .setContentText("AI 对话运行中")
            .setSmallIcon(applicationInfo.icon)
            .setOngoing(true)
            .setShowWhen(false)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .apply { pending?.let { setContentIntent(it) } }
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
            val agent = NativeAgentRegistry.create(agentType)
            agent.initialize(config, this, applicationContext)
            agents[agentId] = agent
            Log.d(TAG, "Created agent: type=$agentType id=$agentId (total=${agents.size})")
            // 兜底：有活跃 agent 即保证前台（onStartCommand 时序异常时也能提升）
            ensureForeground()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create agent: ${e.message}", e)
            onError(agentId, "create_error", e.message ?: "Unknown error", null)
        }
    }

    fun stopAgent(agentId: String) {
        agents.remove(agentId)?.release()
        Log.d(TAG, "Stopped agent: $agentId (remaining=${agents.size})")
        if (agents.isEmpty()) {
            // 最后一个 agent 结束：撤下前台通知并停止 started 状态
            stopForegroundAndSelf()
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
            "detectedLang" to event.detectedLang,
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

    override fun onAgentReady(sessionId: String, ready: Boolean, errorCode: String?, errorMessage: String?) {
        pushEvent(mapOf(
            "type" to "agentReady",
            "sessionId" to sessionId,
            "ready" to ready,
            "errorCode" to errorCode,
            "errorMessage" to errorMessage,
        ))
    }

    private fun pushEvent(data: Map<String, Any?>) {
        eventCallback?.invoke(data)
    }
}
