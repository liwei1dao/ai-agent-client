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
 * AgentsServerPlugin — MethodChannel/EventChannel 调度层
 *
 * 职责：
 * 1. 管理 MethodChannel（Flutter → Native 命令路由）
 * 2. 管理 EventChannel（Native → Flutter 事件转发）
 * 3. 绑定 AgentsServerService，将命令委托给 Service
 *
 * 所有 Agent 管理逻辑在 AgentsServerService 中。
 */
class AgentsServerPlugin : FlutterPlugin {

    companion object {
        private const val TAG = "AgentsServerPlugin"
    }

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSinkStream: EventChannel.EventSink? = null

    private val mainScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private lateinit var context: Context

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
            val svc = service
            if (svc == null && call.method != "notifyAppForeground") {
                Log.w(TAG, "Service not bound, ignoring ${call.method}")
                result.success(null)
                return@setMethodCallHandler
            }

            when (call.method) {
                "createAgent" -> {
                    try {
                        val config = NativeAgentConfig.fromMap(call.arguments<Map<*, *>>()!!)
                        val agentType = call.argument<String>("agentType")!!
                        svc!!.createAgent(agentType, config)
                        result.success(null)
                    } catch (e: Exception) {
                        Log.e(TAG, "createAgent exception: ${e.message}", e)
                        result.error("CREATE_AGENT_ERROR", e.message, null)
                    }
                }
                "stopAgent" -> {
                    svc!!.stopAgent(call.argument<String>("agentId")!!)
                    result.success(null)
                }
                "deleteAgent" -> {
                    svc!!.deleteAgent(call.argument<String>("agentId")!!)
                    result.success(null)
                }
                "sendText" -> {
                    val agentId = call.argument<String>("agentId")!!
                    svc!!.getAgent(agentId)?.sendText(
                        call.argument<String>("requestId")!!,
                        call.argument<String>("text")!!,
                    )
                    result.success(null)
                }
                "setInputMode" -> {
                    val agentId = call.argument<String>("agentId")!!
                    svc!!.getAgent(agentId)?.setInputMode(call.argument<String>("mode")!!)
                    result.success(null)
                }
                "startListening" -> {
                    svc!!.getAgent(call.argument<String>("agentId")!!)?.startListening()
                    result.success(null)
                }
                "stopListening" -> {
                    svc!!.getAgent(call.argument<String>("agentId")!!)?.stopListening()
                    result.success(null)
                }
                "interrupt" -> {
                    svc!!.getAgent(call.argument<String>("agentId")!!)?.interrupt()
                    result.success(null)
                }
                "connectService" -> {
                    Log.d(TAG, "connectService: ${call.argument<String>("agentId")}")
                    result.success(null)
                }
                "disconnectService" -> {
                    val agentId = call.argument<String>("agentId")!!
                    Log.d(TAG, "disconnectService: $agentId")
                    svc!!.getAgent(agentId)?.release()
                    result.success(null)
                }
                "pauseAudio" -> {
                    val agentId = call.argument<String>("agentId")!!
                    svc!!.getAgent(agentId)?.stopListening()
                    result.success(null)
                }
                "resumeAudio" -> {
                    val agentId = call.argument<String>("agentId")!!
                    svc!!.getAgent(agentId)?.startListening()
                    result.success(null)
                }
                "notifyAppForeground" -> {
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

        startServiceAndBind()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        service?.eventCallback = null
        if (isBound) {
            context.unbindService(serviceConnection)
            isBound = false
        }
        mainScope.cancel()
    }

    // ─────────────────────────────────────────────────
    // Service 绑定
    // ─────────────────────────────────────────────────

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            service = (binder as AgentsServerService.LocalBinder).getService()
            isBound = true
            // 设置事件回调：Service → Plugin → EventChannel → Flutter
            service?.eventCallback = { data ->
                mainScope.launch { eventSinkStream?.success(data) }
            }
            Log.d(TAG, "Service bound")
        }
        override fun onServiceDisconnected(name: ComponentName?) {
            service?.eventCallback = null
            service = null
            isBound = false
            Log.d(TAG, "Service unbound")
        }
    }

    private fun startServiceAndBind() {
        val intent = Intent(context, AgentsServerService::class.java)
        context.startForegroundService(intent)
        context.bindService(intent, serviceConnection, Context.BIND_AUTO_CREATE)
    }
}
