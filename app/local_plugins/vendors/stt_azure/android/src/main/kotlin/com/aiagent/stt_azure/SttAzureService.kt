package com.aiagent.stt_azure

import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.NoiseSuppressor
import android.util.Log
import com.aiagent.plugin_interface.ExternalAudioCapability
import com.aiagent.plugin_interface.ExternalAudioFormat
import com.aiagent.plugin_interface.NativeSttService
import com.aiagent.plugin_interface.SttCallback
import com.microsoft.cognitiveservices.speech.*
import com.microsoft.cognitiveservices.speech.audio.AudioConfig
import com.microsoft.cognitiveservices.speech.audio.AudioInputStream
import com.microsoft.cognitiveservices.speech.audio.AudioStreamFormat
import com.microsoft.cognitiveservices.speech.audio.PushAudioInputStream
import com.microsoft.cognitiveservices.speech.AutoDetectSourceLanguageConfig
import com.microsoft.cognitiveservices.speech.AutoDetectSourceLanguageResult
import kotlinx.coroutines.*
import org.json.JSONObject

/**
 * SttAzureService — Azure STT 原生服务实现
 *
 * 实现 NativeSttService 接口，供 Agent 类型插件（agent_chat, agent_translate）直接调用。
 *
 * 合入原 SttPipelineNode 的全部逻辑：
 * - AudioRecord (VOICE_COMMUNICATION) + AEC + NS
 * - PushAudioInputStream → Azure Speech SDK
 * - 连续识别（startContinuousRecognition）
 * - 7 种事件回调
 */
class SttAzureService(private val appContext: Context) : NativeSttService {

    companion object {
        private const val SAMPLE_RATE = 16000
        private const val TAG = "SttAzureService"
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private var isListening = false
    private var recognizer: SpeechRecognizer? = null
    private var speechConfig: SpeechConfig? = null
    private var audioRecord: AudioRecord? = null
    private var pushStream: PushAudioInputStream? = null
    private var aec: AcousticEchoCanceler? = null
    private var ns: NoiseSuppressor? = null
    private var pumpJob: Job? = null
    private var callback: SttCallback? = null

    private var apiKey: String = ""
    private var region: String = ""
    private var language: String = "zh-CN"
    /** 候选语言列表（≥2 时启用 AutoDetect 并在回调中带出 detectedLang）。 */
    private var candidateLanguages: List<String> = emptyList()

    /** true 表示当前 push 流接受外部 PCM；与 startListening (self-mic) 互斥 */
    @Volatile private var externalMode = false
    @Volatile private var externalPushCount = 0L
    @Volatile private var externalPushReportMs = 0L

    // ─────────────────────────────────────────────────
    // NativeSttService 接口实现
    // ─────────────────────────────────────────────────

    override fun initialize(configJson: String, context: Context) {
        val cfg = JSONObject(configJson)
        apiKey = cfg.optString("apiKey", "")
        region = cfg.optString("region", "")
        language = cfg.optString("language", "zh-CN").ifBlank { "zh-CN" }
        // Azure 自动语种识别：BCP-47 语言码列表（如 ["zh-CN", "en-US"]）
        // 超出 4 个 Azure 不支持，取前 4 个。
        val arr = cfg.optJSONArray("languages")
        candidateLanguages = if (arr != null && arr.length() > 0) {
            buildList {
                for (i in 0 until arr.length()) {
                    val s = arr.optString(i, "").trim()
                    if (s.isNotEmpty()) add(s)
                }
            }.distinct().take(4)
        } else emptyList()
        Log.d(TAG, "initialize: region=$region language=$language " +
            "candidateLanguages=$candidateLanguages")
    }

    override fun supportsLanguageDetection(): Boolean = candidateLanguages.size >= 2

    override fun startListening(callback: SttCallback) {
        if (isListening) return
        if (externalMode) {
            callback.onError("stt_busy", "external audio mode active; stopExternalAudio first")
            return
        }
        this.callback = callback
        isListening = true

        scope.launch {
            try {
                setupRecognizer()
                setupSelfMic()
                val ar = audioRecord ?: run {
                    callback.onError("stt_no_audio", "AudioRecord not initialized")
                    isListening = false
                    return@launch
                }
                val ps = pushStream ?: run {
                    callback.onError("stt_no_stream", "PushStream not initialized")
                    isListening = false
                    return@launch
                }

                callback.onListeningStarted()

                // Start AudioRecord
                ar.startRecording()

                // Pump PCM from AudioRecord → PushAudioInputStream
                pumpJob = scope.launch {
                    val buf = ByteArray(3200) // 100ms @ 16kHz 16bit mono
                    while (isActive && ar.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                        val read = ar.read(buf, 0, buf.size)
                        if (read > 0) {
                            if (read == buf.size) {
                                ps.write(buf)
                            } else {
                                ps.write(buf.copyOf(read))
                            }
                        }
                    }
                }

                // Start Azure continuous recognition
                recognizer?.startContinuousRecognitionAsync()?.get()
                Log.d(TAG, "Continuous recognition started")
            } catch (e: CancellationException) {
                // normal
            } catch (e: Exception) {
                Log.e(TAG, "startListening failed: ${e.message}")
                callback.onError("stt_start_error", e.message ?: "Unknown error")
                isListening = false
            }
        }
    }

    override fun stopListening() {
        val wasListening = isListening
        isListening = false
        val hadRecognizer = recognizer != null

        scope.launch {
            try {
                recognizer?.stopContinuousRecognitionAsync()?.get()
            } catch (e: Exception) {
                Log.e(TAG, "stopContinuousRecognitionAsync failed: ${e.message}")
            }
            pumpJob?.cancel()
            pumpJob = null
            runCatching { audioRecord?.stop() }

            // sessionStopped listener fires listeningStopped when recognizer is configured;
            // only fire manually as fallback when STT is not set up.
            if (!hadRecognizer && wasListening) {
                callback?.onListeningStopped()
            }
        }
    }

    override fun release() {
        isListening = false
        externalMode = false
        scope.cancel()
        runCatching { recognizer?.close() }
        runCatching { pushStream?.close() }
        runCatching { audioRecord?.stop(); audioRecord?.release() }
        runCatching { aec?.release() }
        runCatching { ns?.release() }
        recognizer = null
        speechConfig = null
        audioRecord = null
        pushStream = null
        aec = null
        ns = null
        callback = null
    }

    // ─────────────────────────────────────────────────
    // 外部音频源（通话翻译等场景）
    // ─────────────────────────────────────────────────

    override fun externalAudioCapability(): ExternalAudioCapability =
        ExternalAudioCapability(
            acceptsOpus = false,
            acceptsPcm = true,
            preferredSampleRate = SAMPLE_RATE,
            preferredChannels = 1,
            preferredFrameMs = 20,
        )

    override fun startExternalAudio(format: ExternalAudioFormat, callback: SttCallback) {
        if (format.codec != ExternalAudioFormat.Codec.PCM_S16LE) {
            throw IllegalArgumentException(
                "stt_azure accepts only PCM_S16LE (got ${format.codec})")
        }
        if (format.sampleRate != SAMPLE_RATE || format.channels != 1) {
            throw IllegalArgumentException(
                "stt_azure requires ${SAMPLE_RATE}Hz mono " +
                    "(got ${format.sampleRate}Hz/${format.channels}ch)")
        }
        if (isListening) {
            throw IllegalStateException(
                "external audio cannot mix with self-mic mode (stopListening first)")
        }
        if (apiKey.isBlank() || region.isBlank()) {
            callback.onError("stt_config_missing", "apiKey or region is blank")
            return
        }
        this.callback = callback
        externalMode = true

        scope.launch {
            try {
                setupRecognizer()
                callback.onListeningStarted()
                recognizer?.startContinuousRecognitionAsync()?.get()
                Log.d(TAG, "external audio recognition started: " +
                    "${format.sampleRate}Hz mono ${format.frameMs}ms")
            } catch (e: CancellationException) {
                // normal
            } catch (e: Exception) {
                Log.e(TAG, "startExternalAudio failed: ${e.message}")
                callback.onError("stt_start_error", e.message ?: "Unknown error")
                externalMode = false
            }
        }
    }

    override fun pushExternalAudioFrame(frame: ByteArray) {
        if (!externalMode || frame.isEmpty()) return
        val ps = pushStream ?: return
        externalPushCount++
        val now = System.currentTimeMillis()
        if (now - externalPushReportMs >= 1000L) {
            Log.d(TAG, "pushExternalAudioFrame stats (last 1s): count=$externalPushCount bytes=${frame.size}")
            externalPushCount = 0
            externalPushReportMs = now
        }
        runCatching { ps.write(frame) }
    }

    override fun stopExternalAudio() {
        if (!externalMode) return
        externalMode = false
        Log.d(TAG, "stopExternalAudio")
        scope.launch {
            try {
                recognizer?.stopContinuousRecognitionAsync()?.get()
            } catch (e: Exception) {
                Log.e(TAG, "stopContinuousRecognitionAsync failed: ${e.message}")
            }
        }
    }

    // ─────────────────────────────────────────────────
    // 内部实现
    // ─────────────────────────────────────────────────

    /** 建 PushAudioInputStream + SpeechRecognizer + 事件监听（自家 mic 与外部音频共用）。 */
    private fun setupRecognizer() {
        if (recognizer != null) return
        if (apiKey.isBlank() || region.isBlank()) {
            Log.w(TAG, "apiKey or region is blank, STT disabled")
            return
        }

        val format = AudioStreamFormat.getWaveFormatPCM(SAMPLE_RATE.toLong(), 16, 1)
        val ps = AudioInputStream.createPushStream(format)
        pushStream = ps

        val audioConfig = AudioConfig.fromStreamInput(ps)

        speechConfig = SpeechConfig.fromSubscription(apiKey, region).apply {
            // 单语模式时设置识别语言；AutoDetect 模式下由 AutoDetectConfig 提供。
            if (candidateLanguages.size < 2) {
                speechRecognitionLanguage = language
            } else {
                // Continuous 语言识别：每句话都重新检测，避免首句锁定后一直沿用同一语种。
                // 必须在创建 recognizer 之前设置。
                setProperty(
                    PropertyId.SpeechServiceConnection_LanguageIdMode,
                    "Continuous",
                )
            }
        }

        recognizer = if (candidateLanguages.size >= 2) {
            val autoDetect = AutoDetectSourceLanguageConfig.fromLanguages(candidateLanguages)
            Log.d(TAG, "AutoDetect (Continuous) enabled: $candidateLanguages")
            SpeechRecognizer(speechConfig, autoDetect, audioConfig)
        } else {
            SpeechRecognizer(speechConfig, audioConfig)
        }.apply {
            recognizing.addEventListener { _, e ->
                if (e.result.text.isNotBlank()) {
                    val det = detectLangOf(e.result)
                    callback?.onPartialResult(e.result.text, det)
                }
            }
            recognized.addEventListener { _, e ->
                if (e.result.reason == ResultReason.RecognizedSpeech && e.result.text.isNotBlank()) {
                    val det = detectLangOf(e.result)
                    Log.d(TAG, "recognized: lang=$det text='${e.result.text.take(40)}'")
                    callback?.onFinalResult(e.result.text, det)
                }
            }
            speechStartDetected.addEventListener { _, _ ->
                callback?.onVadSpeechStart()
            }
            speechEndDetected.addEventListener { _, _ ->
                callback?.onVadSpeechEnd()
            }
            sessionStopped.addEventListener { _, _ ->
                callback?.onListeningStopped()
            }
            canceled.addEventListener { _, e ->
                if (e.reason == CancellationReason.Error) {
                    callback?.onError(e.errorCode.toString(), e.errorDetails ?: "Unknown")
                }
            }
        }
        Log.d(TAG, "SpeechRecognizer created: region=$region lang=$language")
    }

    /** 从识别结果中读出 detectedLang（AutoDetect 模式下有值；单语模式返回 null）。
     *
     *  老版 SDK 的 [AutoDetectSourceLanguageResult.fromResult] 在 Continuous 模式
     *  下偶尔返回 null，这里回退到 properties 取 raw 字段。 */
    private fun detectLangOf(result: SpeechRecognitionResult): String? {
        if (candidateLanguages.size < 2) return null
        val viaApi = runCatching {
            AutoDetectSourceLanguageResult.fromResult(result)?.language
        }.getOrNull()?.takeIf { it.isNotBlank() }
        if (viaApi != null) return viaApi
        return runCatching {
            result.properties.getProperty(
                PropertyId.SpeechServiceConnection_AutoDetectSourceLanguageResult,
            )
        }.getOrNull()?.takeIf { it.isNotBlank() }
    }

    /** 建本地 AudioRecord + AEC + NS（仅自家 mic 模式需要）。 */
    private fun setupSelfMic() {
        if (audioRecord != null) return
        val minBuf = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        val bufSize = maxOf(minBuf, SAMPLE_RATE * 2 * 2) // at least 2s

        val ar = AudioRecord(
            MediaRecorder.AudioSource.VOICE_COMMUNICATION,
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            bufSize,
        )
        audioRecord = ar

        val audioSessionId = ar.audioSessionId
        if (AcousticEchoCanceler.isAvailable()) {
            aec = AcousticEchoCanceler.create(audioSessionId)?.also { it.enabled = true }
            Log.d(TAG, "AcousticEchoCanceler enabled=${aec?.enabled}")
        } else {
            Log.w(TAG, "AcousticEchoCanceler not available on this device")
        }
        if (NoiseSuppressor.isAvailable()) {
            ns = NoiseSuppressor.create(audioSessionId)?.also { it.enabled = true }
            Log.d(TAG, "NoiseSuppressor enabled=${ns?.enabled}")
        }
    }
}
