package com.aiagent.agents_server

import android.content.*
import android.os.Build
import android.os.IBinder
import android.util.Log
import com.aiagent.plugin_interface.*
import com.aiagent.plugin_interface.AudioOutputManager
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

    /**
     * 本插件实例（= 本 FlutterEngine）注册到 Service 的事件回调引用。
     * 进程内可能存在多个 engine（主 app + 悬浮窗）共享同一单例 Service，必须保留
     * 自己的回调引用以便 detach 时精确注销，不能用单变量覆盖（详见 Service 注释）。
     */
    private val eventCallback: (Map<String, Any?>) -> Unit = { data ->
        mainScope.launch { eventSinkStream?.success(data) }
    }

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
        AudioOutputManager.init(context)

        methodChannel = MethodChannel(binding.binaryMessenger, "agents_server/commands")
        methodChannel.setMethodCallHandler { call, result ->
            // setAudioOutputMode 不依赖 Service，提前处理
            if (call.method == "setAudioOutputMode") {
                val mode = when (call.argument<String>("mode")) {
                    "earpiece" -> AudioOutputManager.Mode.EARPIECE
                    "speaker"  -> AudioOutputManager.Mode.SPEAKER
                    else       -> AudioOutputManager.Mode.AUTO
                }
                AudioOutputManager.setMode(mode)
                result.success(null)
                return@setMethodCallHandler
            }

            // acquireRuntime/releaseRuntime 走 intent action 独立于 binding：
            // 登记/注销一个运行时保活引用（浮窗、音乐等），让进程随宿主服务常驻。
            if (call.method == "acquireRuntime") {
                acquireRuntimeRef(call.argument<String>("tag") ?: "default")
                result.success(null)
                return@setMethodCallHandler
            }
            if (call.method == "releaseRuntime") {
                releaseRuntimeRef(call.argument<String>("tag") ?: "default")
                result.success(null)
                return@setMethodCallHandler
            }

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
                        // 先把 service 提升为 started + foreground，使其脱离 binding 生命周期，
                        // 划掉 app / 锁屏后进程仍存活，BLE + native agent 继续运行。
                        promoteServiceToForeground()
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
                "setAgentOption" -> {
                    val agentId = call.argument<String>("agentId")!!
                    val key = call.argument<String>("key")!!
                    val value = call.argument<String>("value") ?: ""
                    svc!!.getAgent(agentId)?.setOption(key, value)
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
                    val agentId = call.argument<String>("agentId")!!
                    Log.d(TAG, "connectService: $agentId")
                    svc!!.getAgent(agentId)?.connectService()
                    result.success(null)
                }
                "disconnectService" -> {
                    val agentId = call.argument<String>("agentId")!!
                    Log.d(TAG, "disconnectService: $agentId")
                    svc!!.getAgent(agentId)?.disconnectService()
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
        service?.removeEventCallback(eventCallback)
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
            // 注册事件回调：Service → Plugin → EventChannel → Flutter。
            // 用 add 而非赋值，避免多 engine 场景下相互覆盖（详见 Service 注释）。
            service?.addEventCallback(eventCallback)
            Log.d(TAG, "Service bound")
        }
        override fun onServiceDisconnected(name: ComponentName?) {
            service?.removeEventCallback(eventCallback)
            service = null
            isBound = false
            Log.d(TAG, "Service unbound")
        }
    }

    private fun startServiceAndBind() {
        val intent = Intent(context, AgentsServerService::class.java)
        // 仅 bind，不 startForegroundService；foreground 在 createAgent 时按需启动
        context.bindService(intent, serviceConnection, Context.BIND_AUTO_CREATE)
    }

    /**
     * 创建 agent 时调用：startForegroundService 让 Service 成为 started 状态，
     * onStartCommand 内 startForeground 升前台。started 状态使 Service 不随 unbind 销毁，
     * app 被划掉后进程仍由前台服务保活。最后一个 agent 停止时 Service 自行 stopForegroundAndSelf。
     */
    private fun promoteServiceToForeground() {
        val intent = Intent(context, AgentsServerService::class.java).apply {
            action = AgentsServerService.ACTION_ENSURE_FOREGROUND
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
    }

    /**
     * 登记一个运行时保活引用（如桌面浮窗 "overlay"）。走 startForegroundService 触发
     * onStartCommand(ACTION_ACQUIRE_REF)，使 Service 进入 started + foreground 状态、
     * 脱离 binding 生命周期，进程随宿主服务在划掉 app 后仍存活。
     */
    private fun acquireRuntimeRef(tag: String) {
        val intent = Intent(context, AgentsServerService::class.java).apply {
            action = AgentsServerService.ACTION_ACQUIRE_REF
            putExtra(AgentsServerService.EXTRA_REF_TAG, tag)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
    }

    /**
     * 注销一个运行时引用。用 startService（非 foreground）唤起 Service 处理 RELEASE：
     * 若已无任何持有者则 Service 自行退前台并停止，否则按新维度降级 FGS type。
     */
    private fun releaseRuntimeRef(tag: String) {
        val intent = Intent(context, AgentsServerService::class.java).apply {
            action = AgentsServerService.ACTION_RELEASE_REF
            putExtra(AgentsServerService.EXTRA_REF_TAG, tag)
        }
        // Service 已在前台运行（持有引用时必然如此），普通 startService 不受后台启动限制。
        context.startService(intent)
    }
}
