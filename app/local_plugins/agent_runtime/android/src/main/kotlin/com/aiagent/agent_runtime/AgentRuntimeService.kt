package com.aiagent.agent_runtime

import android.app.*
import android.content.Intent
import android.os.Binder
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.aiagent.local_db.AppDatabase

/**
 * AgentRuntimeService — Android ForegroundService
 *
 * 生命周期独立于 Flutter Engine，Agent 可在 App 切后台后继续运行。
 * 通过 LocalBinder 提供 AgentSession 管理接口给 AgentRuntimePlugin。
 */
class AgentRuntimeService : Service() {

    private val sessions = mutableMapOf<String, AgentSession>()
    private lateinit var db: AppDatabase
    lateinit var eventSink: AgentEventSink

    inner class LocalBinder : Binder() {
        fun getService(): AgentRuntimeService = this@AgentRuntimeService
    }

    private val binder = LocalBinder()

    override fun onCreate() {
        super.onCreate()
        db = AppDatabase.getInstance(applicationContext)
        // Delay foreground promotion until a session actually needs audio.
        // Starting with FOREGROUND_SERVICE_MICROPHONE type requires RECORD_AUDIO
        // to be granted first (Android 14+).
    }

    /** Call from plugin after runtime permission is granted. */
    fun promoteToForeground() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, buildNotification(),
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        } else {
            startForeground(NOTIFICATION_ID, buildNotification())
        }
    }

    override fun onBind(intent: Intent): IBinder = binder

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int =
        START_STICKY

    override fun onDestroy() {
        sessions.values.forEach { it.release() }
        sessions.clear()
        super.onDestroy()
    }

    // ─────────────────────────────────────────────────
    // Session 管理
    // ─────────────────────────────────────────────────

    fun startSession(config: AgentSessionConfig) {
        if (sessions.containsKey(config.sessionId)) return
        promoteToForeground()
        val session = AgentSession(config.sessionId, config, db, eventSink, applicationContext)
        sessions[config.sessionId] = session
    }

    fun stopSession(sessionId: String) {
        sessions.remove(sessionId)?.release()
        if (sessions.isEmpty()) stopSelf()
    }

    fun sendText(sessionId: String, requestId: String, text: String) {
        sessions[sessionId]?.sendText(requestId, text)
    }

    fun interrupt(sessionId: String) {
        sessions[sessionId]?.interrupt()
    }

    fun setInputMode(sessionId: String, mode: String) {
        sessions[sessionId]?.setInputMode(mode)
    }

    fun startListening(sessionId: String) {
        sessions[sessionId]?.startListening()
    }

    fun stopListening(sessionId: String) {
        sessions[sessionId]?.stopListening()
    }

    // ─────────────────────────────────────────────────
    // Notification（ForegroundService 必须）
    // ─────────────────────────────────────────────────

    private fun buildNotification(): Notification {
        val channelId = "agent_runtime"
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

    companion object {
        private const val NOTIFICATION_ID = 1001
    }
}
