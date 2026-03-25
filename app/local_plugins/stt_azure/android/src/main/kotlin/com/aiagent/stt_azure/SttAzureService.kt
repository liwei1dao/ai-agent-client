package com.aiagent.stt_azure

import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.NoiseSuppressor
import android.util.Log
import com.aiagent.plugin_interface.NativeSttService
import com.aiagent.plugin_interface.SttCallback
import com.microsoft.cognitiveservices.speech.*
import com.microsoft.cognitiveservices.speech.audio.AudioConfig
import com.microsoft.cognitiveservices.speech.audio.AudioInputStream
import com.microsoft.cognitiveservices.speech.audio.AudioStreamFormat
import com.microsoft.cognitiveservices.speech.audio.PushAudioInputStream
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

    // ─────────────────────────────────────────────────
    // NativeSttService 接口实现
    // ─────────────────────────────────────────────────

    override fun initialize(configJson: String, context: Context) {
        val cfg = JSONObject(configJson)
        apiKey = cfg.optString("apiKey", "")
        region = cfg.optString("region", "")
        language = cfg.optString("language", "zh-CN").ifBlank { "zh-CN" }
        Log.d(TAG, "initialize: region=$region language=$language")
    }

    override fun startListening(callback: SttCallback) {
        if (isListening) return
        this.callback = callback
        isListening = true

        scope.launch {
            try {
                setup()
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
    // 内部实现
    // ─────────────────────────────────────────────────

    private fun setup() {
        if (recognizer != null) return
        if (apiKey.isBlank() || region.isBlank()) {
            Log.w(TAG, "apiKey or region is blank, STT disabled")
            return
        }

        // 1. AudioRecord with VOICE_COMMUNICATION (enables hardware AEC reference)
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

        // 2. Attach AEC + NoiseSuppressor
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

        // 3. PushAudioInputStream → Azure AudioConfig
        val format = AudioStreamFormat.getWaveFormatPCM(SAMPLE_RATE.toLong(), 16, 1)
        val ps = AudioInputStream.createPushStream(format)
        pushStream = ps

        val audioConfig = AudioConfig.fromStreamInput(ps)

        // 4. SpeechRecognizer
        speechConfig = SpeechConfig.fromSubscription(apiKey, region).apply {
            speechRecognitionLanguage = language
        }

        recognizer = SpeechRecognizer(speechConfig, audioConfig).apply {
            recognizing.addEventListener { _, e ->
                if (e.result.text.isNotBlank()) {
                    callback?.onPartialResult(e.result.text)
                }
            }
            recognized.addEventListener { _, e ->
                if (e.result.reason == ResultReason.RecognizedSpeech && e.result.text.isNotBlank()) {
                    callback?.onFinalResult(e.result.text)
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
        Log.d(TAG, "SpeechRecognizer created: region=$region lang=$language AEC=${aec != null}")
    }
}
