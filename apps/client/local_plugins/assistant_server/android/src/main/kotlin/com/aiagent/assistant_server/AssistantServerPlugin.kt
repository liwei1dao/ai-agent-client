package com.aiagent.assistant_server

import android.content.Context
import android.util.Log
import com.aiagent.plugin_interface.NativeAgentConfig
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.util.UUID

/**
 * assistant_server Flutter plugin —— Method/Event channel 入口。
 *
 *  - method channel `assistant_server/method`:
 *      • startAssistant(arg: Map) → returns sessionId
 *      • stopActiveSession()
 *      • activeSessionId() → returns String?
 *  - event channel `assistant_server/events`:
 *      消息 / 状态 / 错误 / 连接状态（详见 [AssistantEvents]）
 *
 * 编排逻辑全部在 [AssistantServerCore] / [AssistantSession]，本类只做调度。
 */
class AssistantServerPlugin : FlutterPlugin {

    companion object {
        private const val TAG = "AssistantServerPlugin"
    }

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null
    private val mainScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private lateinit var appContext: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext

        eventChannel = EventChannel(binding.binaryMessenger, "assistant_server/events")
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                AssistantServerCore.bindEmitter { payload ->
                    mainScope.launch { runCatching { events?.success(payload) } }
                }
            }
            override fun onCancel(arguments: Any?) {
                AssistantServerCore.unbindEmitter()
                eventSink = null
            }
        })

        methodChannel = MethodChannel(binding.binaryMessenger, "assistant_server/method")
        methodChannel.setMethodCallHandler { call, result ->
            try {
                handleMethod(call, result)
            } catch (e: Exception) {
                Log.e(TAG, "method ${call.method} failed", e)
                result.error(e::class.java.simpleName, e.message, null)
            }
        }
    }

    private fun handleMethod(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startAssistant" -> {
                val args = call.arguments as? Map<*, *>
                    ?: return result.error("InvalidArgument", "arguments must be a map", null)
                val req = parseRequest(args)
                val sessionId = (args["sessionId"] as? String)
                    ?: ("as_${System.currentTimeMillis()}_${UUID.randomUUID().toString().take(6)}")
                val id = AssistantServerCore.startAssistant(sessionId, req, appContext)
                result.success(id)
            }

            "stopActiveSession" -> {
                AssistantServerCore.stopActive()
                result.success(null)
            }

            "activeSessionId" -> {
                result.success(AssistantServerCore.activeSessionId())
            }

            else -> result.notImplemented()
        }
    }

    private fun parseRequest(args: Map<*, *>): AssistantRequest {
        val agentType = args["agentType"] as? String
            ?: error("agentType required")
        val agentConfigMap = (args["agentConfig"] as? Map<*, *>)
            ?: error("agentConfig required")
        val userLanguage = (args["userLanguage"] as? String) ?: ""

        return AssistantRequest(
            agentType = agentType,
            agentConfig = NativeAgentConfig.fromMap(agentConfigMap),
            userLanguage = userLanguage,
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        AssistantServerCore.unbindEmitter()
        AssistantServerCore.stopActive()
        mainScope.cancel()
    }
}
