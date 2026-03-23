package com.aiagent.stt_azure

import com.microsoft.cognitiveservices.speech.*
import com.microsoft.cognitiveservices.speech.audio.AudioConfig
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

/**
 * SttAzurePlugin — Azure 语音识别 Flutter 插件
 *
 * 命令通道：stt_azure/commands
 *   - initialize(apiKey, region, language)
 *   - startListening
 *   - stopListening
 *
 * 事件通道：stt_azure/events
 *   推送 7 种 STT 事件 Map：
 *   { kind: String, text: String?, errorCode: String?, errorMessage: String? }
 */
class SttAzurePlugin : FlutterPlugin {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null

    private val mainScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var recognizer: SpeechRecognizer? = null
    private var speechConfig: SpeechConfig? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
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
    // 实现
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
            // 识别中（partial result）
            recognizing.addEventListener { _, e ->
                pushEvent(mapOf("kind" to "partialResult", "text" to e.result.text))
            }
            // 识别完成（final result）
            recognized.addEventListener { _, e ->
                if (e.result.reason == ResultReason.RecognizedSpeech) {
                    pushEvent(mapOf("kind" to "finalResult", "text" to e.result.text))
                }
            }
            // 会话开始
            sessionStarted.addEventListener { _, _ ->
                pushEvent(mapOf("kind" to "listeningStarted"))
            }
            // 会话结束
            sessionStopped.addEventListener { _, _ ->
                pushEvent(mapOf("kind" to "listeningStopped"))
            }
            // 静音检测开始语音
            speechStartDetected.addEventListener { _, _ ->
                pushEvent(mapOf("kind" to "vadSpeechStart"))
            }
            // 静音检测结束语音
            speechEndDetected.addEventListener { _, _ ->
                pushEvent(mapOf("kind" to "vadSpeechEnd"))
            }
            // 错误
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
