package com.aiagent.translate_server

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
 * translate_server Flutter plugin —— Method/Event channel 入口。
 *
 *  - method channel `translate_server/method`:
 *      • startCallTranslation(arg: Map) → returns sessionId
 *      • stopActiveSession()
 *      • activeSessionId() → returns String?
 *  - event channel `translate_server/events`:
 *      字幕 / 状态 / 错误 / 连接状态（详见 [TranslateEvents]）
 *
 * 编排逻辑全部在 [TranslateServerCore] / [CallTranslationSession]，本类只做调度。
 */
class TranslateServerPlugin : FlutterPlugin {

    companion object {
        private const val TAG = "TranslateServerPlugin"
    }

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null
    private val mainScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private lateinit var appContext: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext

        eventChannel = EventChannel(binding.binaryMessenger, "translate_server/events")
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                TranslateServerCore.bindEmitter { payload ->
                    mainScope.launch { runCatching { events?.success(payload) } }
                }
            }
            override fun onCancel(arguments: Any?) {
                TranslateServerCore.unbindEmitter()
                eventSink = null
            }
        })

        methodChannel = MethodChannel(binding.binaryMessenger, "translate_server/method")
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
            "startCallTranslation" -> {
                val args = call.arguments as? Map<*, *>
                    ?: return result.error("InvalidArgument", "arguments must be a map", null)
                val req = parseCallRequest(args)
                val sessionId = (args["sessionId"] as? String)
                    ?: ("ts_${System.currentTimeMillis()}_${UUID.randomUUID().toString().take(6)}")
                val id = TranslateServerCore.startCallTranslation(sessionId, req, appContext)
                result.success(id)
            }

            "stopActiveSession" -> {
                TranslateServerCore.stopActive()
                result.success(null)
            }

            "activeSessionId" -> {
                result.success(TranslateServerCore.activeSessionId())
            }

            "startFaceToFaceTranslation",
            "startAudioTranslation" -> {
                result.error("translate.not_implemented",
                    "${call.method} not implemented yet", null)
            }

            else -> result.notImplemented()
        }
    }

    private fun parseCallRequest(args: Map<*, *>): CallTranslationRequest {
        val uplinkAgentType = args["uplinkAgentType"] as? String
            ?: error("uplinkAgentType required")
        val downlinkAgentType = args["downlinkAgentType"] as? String
            ?: error("downlinkAgentType required")
        val uplinkConfigMap = (args["uplinkConfig"] as? Map<*, *>)
            ?: error("uplinkConfig required")
        val downlinkConfigMap = (args["downlinkConfig"] as? Map<*, *>)
            ?: error("downlinkConfig required")
        val userLanguage = (args["userLanguage"] as? String) ?: ""
        val peerLanguage = (args["peerLanguage"] as? String) ?: ""

        return CallTranslationRequest(
            uplinkAgentType = uplinkAgentType,
            uplinkConfig = NativeAgentConfig.fromMap(uplinkConfigMap),
            downlinkAgentType = downlinkAgentType,
            downlinkConfig = NativeAgentConfig.fromMap(downlinkConfigMap),
            userLanguage = userLanguage,
            peerLanguage = peerLanguage,
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        TranslateServerCore.unbindEmitter()
        TranslateServerCore.stopActive()
        mainScope.cancel()
    }
}
