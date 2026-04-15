package com.aiagent.service_manager

import android.content.Context
import android.util.Log
import com.aiagent.plugin_interface.ServiceTestEventSink
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

/**
 * ServiceManagerPlugin — MethodChannel/EventChannel 调度层
 *
 * 职责：
 * 1. 管理 MethodChannel（Flutter → Native 命令路由）
 * 2. 管理 EventChannel（Native → Flutter 事件转发）
 * 3. 创建 ServiceTestRunner，将命令委托过去
 *
 * 对应 AgentsServerPlugin 的角色，但管的是服务测试而不是 Agent。
 */
class ServiceManagerPlugin : FlutterPlugin, ServiceTestEventSink {

    companion object {
        private const val TAG = "ServiceManagerPlugin"
    }

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSinkStream: EventChannel.EventSink? = null

    private val mainScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private lateinit var context: Context
    private var runner: ServiceTestRunner? = null

    // ─────────────────────────────────────────────────
    // FlutterPlugin 生命周期
    // ─────────────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        runner = ServiceTestRunner(context, this)

        methodChannel = MethodChannel(binding.binaryMessenger, "service_manager/commands")
        methodChannel.setMethodCallHandler { call, result ->
            val r = runner
            if (r == null) {
                Log.w(TAG, "Runner not ready, ignoring ${call.method}")
                result.success(null)
                return@setMethodCallHandler
            }

            when (call.method) {
                // ── STT ──
                "testSttStart" -> {
                    r.testSttStart(
                        testId = call.argument<String>("testId")!!,
                        serviceId = call.argument<String>("serviceId")!!,
                    )
                    result.success(null)
                }
                "testSttStop" -> {
                    r.testSttStop(call.argument<String>("testId")!!)
                    result.success(null)
                }

                // ── TTS ──
                "testTtsSpeak" -> {
                    r.testTtsSpeak(
                        testId = call.argument<String>("testId")!!,
                        serviceId = call.argument<String>("serviceId")!!,
                        text = call.argument<String>("text")!!,
                        voiceName = call.argument<String>("voiceName"),
                        speed = call.argument<Double>("speed") ?: 1.0,
                        pitch = call.argument<Double>("pitch") ?: 1.0,
                    )
                    result.success(null)
                }
                "testTtsStop" -> {
                    r.testTtsStop(call.argument<String>("testId")!!)
                    result.success(null)
                }

                // ── LLM ──
                "testLlmChat" -> {
                    r.testLlmChat(
                        testId = call.argument<String>("testId")!!,
                        serviceId = call.argument<String>("serviceId")!!,
                        text = call.argument<String>("text")!!,
                    )
                    result.success(null)
                }
                "testLlmCancel" -> {
                    r.testLlmCancel(call.argument<String>("testId")!!)
                    result.success(null)
                }

                // ── Translation ──
                "testTranslate" -> {
                    r.testTranslate(
                        testId = call.argument<String>("testId")!!,
                        serviceId = call.argument<String>("serviceId")!!,
                        text = call.argument<String>("text")!!,
                        targetLang = call.argument<String>("targetLang")!!,
                        sourceLang = call.argument<String>("sourceLang"),
                    )
                    result.success(null)
                }

                // ── STS ──
                "testStsConnect" -> {
                    r.testStsConnect(
                        testId = call.argument<String>("testId")!!,
                        serviceId = call.argument<String>("serviceId")!!,
                    )
                    result.success(null)
                }
                "testStsStartAudio" -> {
                    r.testStsStartAudio(call.argument<String>("testId")!!)
                    result.success(null)
                }
                "testStsStopAudio" -> {
                    r.testStsStopAudio(call.argument<String>("testId")!!)
                    result.success(null)
                }
                "testStsDisconnect" -> {
                    r.testStsDisconnect(call.argument<String>("testId")!!)
                    result.success(null)
                }

                // ── AST ──
                "testAstConnect" -> {
                    r.testAstConnect(
                        testId = call.argument<String>("testId")!!,
                        serviceId = call.argument<String>("serviceId")!!,
                    )
                    result.success(null)
                }
                "testAstStartAudio" -> {
                    r.testAstStartAudio(call.argument<String>("testId")!!)
                    result.success(null)
                }
                "testAstStopAudio" -> {
                    r.testAstStopAudio(call.argument<String>("testId")!!)
                    result.success(null)
                }
                "testAstDisconnect" -> {
                    r.testAstDisconnect(call.argument<String>("testId")!!)
                    result.success(null)
                }

                // ── 自动化测试 ──
                "autoTest" -> {
                    r.autoTest(
                        testId = call.argument<String>("testId")!!,
                        serviceId = call.argument<String>("serviceId")!!,
                    )
                    result.success(null)
                }

                // ── 通用 ──
                "releaseTest" -> {
                    r.releaseSession(call.argument<String>("testId")!!)
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        eventChannel = EventChannel(binding.binaryMessenger, "service_manager/events")
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSinkStream = events
            }
            override fun onCancel(arguments: Any?) {
                eventSinkStream = null
            }
        })
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        runner?.releaseAll()
        runner = null
        mainScope.cancel()
    }

    // ─────────────────────────────────────────────────
    // ServiceTestEventSink 实现（Runner → Plugin → EventChannel → Flutter）
    // ─────────────────────────────────────────────────

    override fun onSttTestEvent(testId: String, kind: String, text: String?, errorCode: String?, errorMessage: String?) {
        pushEvent(mapOf(
            "type" to "stt",
            "testId" to testId,
            "kind" to kind,
            "text" to text,
            "errorCode" to errorCode,
            "errorMessage" to errorMessage,
        ))
    }

    override fun onTtsTestEvent(testId: String, kind: String, progressMs: Int?, durationMs: Int?, errorCode: String?, errorMessage: String?) {
        pushEvent(mapOf(
            "type" to "tts",
            "testId" to testId,
            "kind" to kind,
            "progressMs" to progressMs,
            "durationMs" to durationMs,
            "errorCode" to errorCode,
            "errorMessage" to errorMessage,
        ))
    }

    override fun onLlmTestEvent(testId: String, kind: String, textDelta: String?, thinkingDelta: String?, toolCallId: String?, toolName: String?, toolArgumentsDelta: String?, toolResult: String?, fullText: String?, errorCode: String?, errorMessage: String?) {
        pushEvent(mapOf(
            "type" to "llm",
            "testId" to testId,
            "kind" to kind,
            "textDelta" to textDelta,
            "thinkingDelta" to thinkingDelta,
            "toolCallId" to toolCallId,
            "toolName" to toolName,
            "toolArgumentsDelta" to toolArgumentsDelta,
            "toolResult" to toolResult,
            "fullText" to fullText,
            "errorCode" to errorCode,
            "errorMessage" to errorMessage,
        ))
    }

    override fun onTranslationTestEvent(testId: String, kind: String, sourceText: String?, translatedText: String?, sourceLanguage: String?, targetLanguage: String?, errorCode: String?, errorMessage: String?) {
        pushEvent(mapOf(
            "type" to "translation",
            "testId" to testId,
            "kind" to kind,
            "sourceText" to sourceText,
            "translatedText" to translatedText,
            "sourceLanguage" to sourceLanguage,
            "targetLanguage" to targetLanguage,
            "errorCode" to errorCode,
            "errorMessage" to errorMessage,
        ))
    }

    override fun onStsTestEvent(testId: String, kind: String, text: String?, state: String?, errorCode: String?, errorMessage: String?) {
        pushEvent(mapOf(
            "type" to "sts",
            "testId" to testId,
            "kind" to kind,
            "text" to text,
            "state" to state,
            "errorCode" to errorCode,
            "errorMessage" to errorMessage,
        ))
    }

    override fun onAstTestEvent(testId: String, kind: String, text: String?, state: String?, errorCode: String?, errorMessage: String?) {
        pushEvent(mapOf(
            "type" to "ast",
            "testId" to testId,
            "kind" to kind,
            "text" to text,
            "state" to state,
            "errorCode" to errorCode,
            "errorMessage" to errorMessage,
        ))
    }

    override fun onTestDone(testId: String, success: Boolean, message: String?) {
        pushEvent(mapOf(
            "type" to "done",
            "testId" to testId,
            "success" to success,
            "message" to message,
        ))
    }

    private fun pushEvent(data: Map<String, Any?>) {
        mainScope.launch { eventSinkStream?.success(data) }
    }
}
