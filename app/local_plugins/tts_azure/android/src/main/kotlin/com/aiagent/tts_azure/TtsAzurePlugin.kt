package com.aiagent.tts_azure

import com.microsoft.cognitiveservices.speech.*
import com.microsoft.cognitiveservices.speech.audio.AudioConfig
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

/**
 * TtsAzurePlugin — Azure 语音合成 Flutter 插件
 *
 * 命令通道：tts_azure/commands
 *   - initialize(apiKey, region, voiceName, outputFormat)
 *   - speak(text, requestId)
 *   - stop
 *
 * 事件通道：tts_azure/events
 *   推送 7 种 TTS 事件 Map：
 *   { kind, requestId, progressMs?, durationMs?, errorCode?, errorMessage? }
 */
class TtsAzurePlugin : FlutterPlugin {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null

    private val mainScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var synthesizer: SpeechSynthesizer? = null
    private var speechConfig: SpeechConfig? = null
    private var currentRequestId: String = ""

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel = MethodChannel(binding.binaryMessenger, "tts_azure/commands")
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> {
                    val key = call.argument<String>("apiKey")!!
                    val region = call.argument<String>("region")!!
                    val voice = call.argument<String>("voiceName") ?: "zh-CN-XiaoxiaoNeural"
                    initialize(key, region, voice)
                    result.success(null)
                }
                "speak" -> {
                    val text = call.argument<String>("text")!!
                    val reqId = call.argument<String>("requestId") ?: ""
                    speak(text, reqId)
                    result.success(null)
                }
                "stop" -> {
                    stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        eventChannel = EventChannel(binding.binaryMessenger, "tts_azure/events")
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink?) { eventSink = sink }
            override fun onCancel(args: Any?) { eventSink = null }
        })
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        synthesizer?.close()
        speechConfig?.close()
        mainScope.cancel()
    }

    // ─────────────────────────────────────────────────
    // 实现
    // ─────────────────────────────────────────────────

    private fun initialize(apiKey: String, region: String, voiceName: String) {
        synthesizer?.close()
        speechConfig?.close()

        speechConfig = SpeechConfig.fromSubscription(apiKey, region).apply {
            speechSynthesisVoiceName = voiceName
            setSpeechSynthesisOutputFormat(SpeechSynthesisOutputFormat.Audio16Khz128KBitRateMonoMp3)
        }

        val audioConfig = AudioConfig.fromDefaultSpeakerOutput()
        synthesizer = SpeechSynthesizer(speechConfig, audioConfig).apply {
            // 合成开始
            SynthesisStarted.addEventListener { _, _ ->
                pushEvent(mapOf("kind" to "synthesisStart", "requestId" to currentRequestId))
            }
            // 合成完成（数据就绪）
            Synthesizing.addEventListener { _, e ->
                val audioDuration = e.result.audioDuration
                pushEvent(mapOf(
                    "kind" to "synthesisReady",
                    "requestId" to currentRequestId,
                    "durationMs" to (audioDuration / 10_000L).toInt(), // 100ns → ms
                ))
            }
            // 播放开始（SDK 开始向扬声器写入）
            SynthesisCompleted.addEventListener { _, _ ->
                pushEvent(mapOf("kind" to "playbackStart", "requestId" to currentRequestId))
                // Azure SDK 播放完即触发 completed，推送 playbackDone
                pushEvent(mapOf("kind" to "playbackDone", "requestId" to currentRequestId))
            }
            // 取消/错误
            SynthesisCanceled.addEventListener { _, e ->
                val detail = SpeechSynthesisCancellationDetails.fromResult(e.result)
                if (detail.reason == CancellationReason.Error) {
                    pushEvent(mapOf(
                        "kind" to "error",
                        "requestId" to currentRequestId,
                        "errorCode" to detail.errorCode.toString(),
                        "errorMessage" to detail.errorDetails,
                    ))
                } else {
                    pushEvent(mapOf("kind" to "playbackInterrupted", "requestId" to currentRequestId))
                }
            }
        }
    }

    private fun speak(text: String, requestId: String) {
        currentRequestId = requestId
        pushEvent(mapOf("kind" to "synthesisStart", "requestId" to requestId))
        mainScope.launch(Dispatchers.IO) {
            synthesizer?.SpeakTextAsync(text)?.get()
        }
    }

    private fun stop() {
        synthesizer?.StopSpeakingAsync()
        pushEvent(mapOf("kind" to "playbackInterrupted", "requestId" to currentRequestId))
    }

    private fun pushEvent(data: Map<String, Any?>) {
        mainScope.launch { eventSink?.success(data) }
    }
}
