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
 * AgentsServerService — 助理运行时宿主服务（前台保活）
 *
 * 职责：
 * 1. 持有所有活跃 NativeAgent 实例的生命周期（创建/停止/删除）
 * 2. 实现 AgentEventSink，接收 Agent 事件
 * 3. 通过 eventCallback 将事件转发给 Plugin 层（→ EventChannel → Flutter）
 * 4. 作为 **started + foreground** 服务运行：只要进程内还有任一"在线持有者"
 *    （活跃 agent / 桌面浮窗 / 音乐播放 …）就保持前台，使整个进程在锁屏/切后台/
 *    划掉 app 时不被系统回收。
 *
 * 「在线持有者」分两类：
 * - 活跃 agent（[agents] 非空）——createAgent/stopAgent 自动登记/注销；
 * - 显式运行时引用（[runtimeRefs]）——浮窗、音乐等子能力通过 acquireRef/releaseRef 登记。
 *
 * 前台服务 type 随当前活跃维度动态合并（[computeForegroundType]）：有 agent →
 * microphone+connectedDevice；有 music → mediaPlayback；仅浮窗等 → specialUse 兜底。
 *
 * Plugin 层只做 MethodChannel 调度，将命令委托给此 Service；保活的提升/降级/退出统一
 * 走 [onStartCommand] 的 action 分派，从而独立于 binding 生命周期。
 */
class AgentsServerService : Service(), AgentEventSink {

    companion object {
        private const val TAG = "AgentsServerService"

        const val ACTION_ENSURE_FOREGROUND = "com.aiagent.agents_server.ENSURE_FOREGROUND"
        const val ACTION_ACQUIRE_REF = "com.aiagent.agents_server.ACQUIRE_REF"
        const val ACTION_RELEASE_REF = "com.aiagent.agents_server.RELEASE_REF"
        const val EXTRA_REF_TAG = "ref_tag"

        /** 运行时引用标签：桌面浮窗常驻。 */
        const val REF_OVERLAY = "overlay"
        /** 运行时引用标签：音乐播放（触发 mediaPlayback FGS type）。 */
        const val REF_MUSIC = "music"

        private const val CHANNEL_ID = "agents_server_running"
        private const val CHANNEL_NAME = "AI 对话运行中"
        private const val NOTIFICATION_ID = 0x4147 // 'AG'
    }

    /** 是否已处于前台状态，避免重复 startForeground */
    private var isForeground = false

    /** 当前已应用的前台 type，用于判断是否需要因 type 变化重新 startForeground。 */
    private var currentFgsType = 0

    inner class LocalBinder : Binder() {
        fun getService(): AgentsServerService = this@AgentsServerService
    }

    private val binder = LocalBinder()

    /** 活跃 Agent 实例: agentId → NativeAgent */
    private val agents = mutableMapOf<String, NativeAgent>()

    /** 显式运行时引用（浮窗 / 音乐 …）；与 [agents] 一起决定进程是否保活。 */
    private val runtimeRefs = mutableSetOf<String>()

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
     * 保活的提升/降级/退出统一入口，按 action 分派：
     * - ACTION_ACQUIRE_REF：登记一个运行时引用（浮窗/音乐），刷新前台（必要时改 type）；
     * - ACTION_RELEASE_REF：注销引用，若已无任何持有者则退前台并停止，否则降级 type；
     * - 其它（ACTION_ENSURE_FOREGROUND / 进程被回收后的 null 重启）：按当前状态刷新前台。
     *
     * 必须在 5s 内调用 startForeground，否则系统抛 ANR；各分支都会立即 [refreshForeground]。
     * START_STICKY：进程被系统回收后，资源允许时重建 service（intent 为 null）。
     */
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_ACQUIRE_REF -> {
                val tag = intent.getStringExtra(EXTRA_REF_TAG) ?: "default"
                runtimeRefs.add(tag)
                Log.d(TAG, "acquireRef: $tag (refs=$runtimeRefs)")
                refreshForeground()
            }
            ACTION_RELEASE_REF -> {
                val tag = intent.getStringExtra(EXTRA_REF_TAG) ?: "default"
                runtimeRefs.remove(tag)
                Log.d(TAG, "releaseRef: $tag (refs=$runtimeRefs)")
                stopIfIdleElseRefresh()
            }
            else -> refreshForeground()
        }
        return START_STICKY
    }

    /**
     * 用户从最近任务划掉 app。只要还有任一在线持有者（活跃 agent 或运行时引用），
     * 就保持前台服务运行（不 stopSelf），让 BLE + native agent + 浮窗在无 UI 状态下继续；
     * 没有任何持有者时正常退出。
     */
    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.d(TAG, "onTaskRemoved: agents=${agents.size} refs=$runtimeRefs")
        if (!shouldStayAlive()) {
            stopForegroundAndSelf()
        }
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        agents.values.forEach { it.release() }
        agents.clear()
        runtimeRefs.clear()
        eventCallback = null
        if (isForeground) {
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
            isForeground = false
            currentFgsType = 0
        }
        super.onDestroy()
    }

    // ─────────────────────────────────────────────────
    // 前台服务保活
    // ─────────────────────────────────────────────────

    /** 是否还有在线持有者（活跃 agent 或运行时引用），决定进程是否保活。 */
    private fun shouldStayAlive(): Boolean = agents.isNotEmpty() || runtimeRefs.isNotEmpty()

    /** 引用/agent 注销后调用：无持有者则退前台并停止，否则按新维度刷新前台 type。 */
    private fun stopIfIdleElseRefresh() {
        if (shouldStayAlive()) refreshForeground() else stopForegroundAndSelf()
    }

    /**
     * 按当前活跃维度合并前台服务 type：
     * - 有活跃 agent → microphone + connectedDevice（录音 + BLE 耳机）；
     * - 有 music 引用 → mediaPlayback；
     * - 仅浮窗等无媒体维度 → specialUse 兜底（FGS 必须至少声明一种 type）。
     *
     * Android < R（API 30）不支持带 type 的 startForeground，返回 0（ServiceCompat 忽略 type）。
     */
    private fun computeForegroundType(): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return 0
        var type = 0
        if (agents.isNotEmpty()) {
            type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
        }
        if (runtimeRefs.contains(REF_MUSIC)) {
            type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
        }
        if (type == 0) {
            // 仅浮窗等：无麦克风/媒体维度时用 specialUse 维持前台。
            // specialUse 常量需 API 34；API 30-33 上退回 connectedDevice 兜底保活。
            type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            } else {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
            }
        }
        return type
    }

    /**
     * 提升/刷新前台服务（幂等）。未在前台则提升；已在前台但目标 type 变化（如 agent 启动
     * 让 specialUse → microphone）则以新 type 重新 startForeground。
     */
    private fun refreshForeground() {
        val targetType = computeForegroundType()
        if (isForeground && targetType == currentFgsType) return
        try {
            ServiceCompat.startForeground(this, NOTIFICATION_ID, buildNotification(), targetType)
            isForeground = true
            currentFgsType = targetType
            Log.d(TAG, "foreground refreshed: type=$targetType")
        } catch (e: Exception) {
            // Android 12+ 后台启动前台服务受限（ForegroundServiceStartNotAllowedException）等
            Log.e(TAG, "startForeground failed: ${e.message}", e)
        }
    }

    private fun stopForegroundAndSelf() {
        if (isForeground) {
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
            isForeground = false
            currentFgsType = 0
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
            // 兜底：有活跃 agent 即保证前台（onStartCommand 时序异常时也能提升），
            // 并把 type 升到 microphone+connectedDevice（覆盖之前可能的 specialUse）。
            refreshForeground()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create agent: ${e.message}", e)
            onError(agentId, "create_error", e.message ?: "Unknown error", null)
        }
    }

    fun stopAgent(agentId: String) {
        agents.remove(agentId)?.release()
        Log.d(TAG, "Stopped agent: $agentId (remaining=${agents.size})")
        // 最后一个 agent 结束：若仍有运行时引用（如浮窗常驻）则只降级 type，否则退前台并停止。
        stopIfIdleElseRefresh()
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
