package com.aiagent.stt_azure

import android.util.Log
import com.aiagent.plugin_interface.NativeServiceRegistry
import com.microsoft.cognitiveservices.speech.*
import com.microsoft.cognitiveservices.speech.audio.AudioConfig
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

/**
 * SttAzurePlugin — Azure 语音识别 Flutter 插件
 *
 * 双重角色：
 * 1. NativeServiceRegistry 注册：Agent 类型插件通过 NativeSttService 接口直接调用
 * 2. MethodChannel/EventChannel：保留 Dart 桥接（向后兼容）
 */
class SttAzurePlugin : FlutterPlugin {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null

    private val mainScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var recognizer: SpeechRecognizer? = null
    private var speechConfig: SpeechConfig? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val context = binding.applicationContext

        // ── 注册到 NativeServiceRegistry（供 Agent 类型插件原生调用）──
        NativeServiceRegistry.registerStt("azure") { SttAzureService(context) }
        Log.d("SttAzurePlugin", "Registered NativeSttService vendor=azure")

        // ── 保留 MethodChannel/EventChannel（Dart 桥接，向后兼容）──
        methodChannel = MethodChannel(binding.binaryMessenger, "stt_azure/commands")
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> {
                    val key = call.argument<String>("apiKey")!!
                    val region = call.argument<String>("region")!!
                    val lang = call.argument<String>("language") ?: "zh-CN"
                    mainScope.launch(Dispatchers.IO) {
                        try {
                            initialize(key, region, lang)
                            withContext(Dispatchers.Main) { result.success(null) }
                        } catch (e: Exception) {
                            withContext(Dispatchers.Main) { result.error("STT_INIT", e.message, null) }
                        }
                    }
                }
                "startListening" -> {
                    startListening()
                    result.success(null)
                }
                "stopListening" -> {
                    stopListening()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        eventChannel = EventChannel(binding.binaryMessenger, "stt_azure/events")
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink?) { eventSink = sink }
            override fun onCancel(args: Any?) { eventSink = null }
        })
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        recognizer?.close()
        speechConfig?.close()
        mainScope.cancel()
    }

    // ─────────────────────────────────────────────────
    // Dart MethodChannel 实现（向后兼容）
    // ─────────────────────────────────────────────────

    private fun initialize(apiKey: String, region: String, language: String) {
        recognizer?.close()
        speechConfig?.close()

        speechConfig = SpeechConfig.fromSubscription(apiKey, region).apply {
            speechRecognitionLanguage = language
            setProperty(PropertyId.SpeechServiceResponse_RequestDetailedResultTrueFalse, "true")
        }

        val audioConfig = AudioConfig.fromDefaultMicrophoneInput()
        recognizer = SpeechRecognizer(speechConfig, audioConfig).apply {
            recognizing.addEventListener { _, e ->
                pushEvent(mapOf("kind" to "partialResult", "text" to e.result.text))
            }
            recognized.addEventListener { _, e ->
                if (e.result.reason == ResultReason.RecognizedSpeech) {
                    pushEvent(mapOf("kind" to "finalResult", "text" to e.result.text))
                }
            }
            sessionStarted.addEventListener { _, _ ->
                pushEvent(mapOf("kind" to "listeningStarted"))
            }
            sessionStopped.addEventListener { _, _ ->
                pushEvent(mapOf("kind" to "listeningStopped"))
            }
            speechStartDetected.addEventListener { _, _ ->
                pushEvent(mapOf("kind" to "vadSpeechStart"))
            }
            speechEndDetected.addEventListener { _, _ ->
                pushEvent(mapOf("kind" to "vadSpeechEnd"))
            }
            canceled.addEventListener { _, e ->
                if (e.reason == CancellationReason.Error) {
                    pushEvent(mapOf(
                        "kind" to "error",
                        "errorCode" to e.errorCode.toString(),
                        "errorMessage" to e.errorDetails,
                    ))
                }
            }
        }
    }

    private fun startListening() {
        val r = recognizer ?: return
        mainScope.launch(Dispatchers.IO) {
            r.startContinuousRecognitionAsync().get()
        }
    }

    private fun stopListening() {
        val r = recognizer ?: return
        mainScope.launch(Dispatchers.IO) {
            r.stopContinuousRecognitionAsync().get()
        }
    }

    private fun pushEvent(data: Map<String, Any?>) {
        mainScope.launch { eventSink?.success(data) }
    }
}
