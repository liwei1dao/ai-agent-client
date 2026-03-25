package com.aiagent.agents_server

import android.app.*
import android.content.Intent
import android.os.Binder
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * AgentsServerService — Android ForegroundService
 *
 * 精简版：仅负责前台服务保活 + 通知栏。
 * 不包含任何 Agent/Session 管理逻辑（全部在 AgentsServerPlugin 中）。
 */
class AgentsServerService : Service() {

    inner class LocalBinder : Binder() {
        fun getService(): AgentsServerService = this@AgentsServerService
    }

    private val binder = LocalBinder()

    override fun onCreate() {
        super.onCreate()
    }

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

    override fun onBind(intent: Intent): IBinder = binder

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY

    override fun onDestroy() {
        super.onDestroy()
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

    companion object {
        private const val NOTIFICATION_ID = 1001
    }
}
