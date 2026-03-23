package com.aiagent.agent_runtime.pipeline

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.NoiseSuppressor
import android.util.Log
import com.aiagent.agent_runtime.*
import com.aiagent.local_db.AppDatabase
import com.microsoft.cognitiveservices.speech.*
import com.microsoft.cognitiveservices.speech.audio.AudioConfig
import com.microsoft.cognitiveservices.speech.audio.AudioInputStream
import com.microsoft.cognitiveservices.speech.audio.AudioStreamFormat
import com.microsoft.cognitiveservices.speech.audio.PushAudioInputStream
import kotlinx.coroutines.*
import org.json.JSONObject
import java.util.UUID

/**
 * SttPipelineNode — 调用 Azure STT SDK，推送 7 种 STT 事件
 *
 * 使用 AudioSource.VOICE_COMMUNICATION + AcousticEchoCanceler 消除回音：
 *   1. 创建 AudioRecord（VOICE_COMMUNICATION 源）
 *   2. 挂载 AcousticEchoCanceler / NoiseSuppressor
 *   3. 用 PushAudioInputStream 把 PCM 数据喂给 Azure
 *   4. Azure 在云端做 VAD / ASR
 *
 * 打断逻辑：
 *   speechStartDetected → onSpeechStart() → AgentSession.interruptForVoiceInput()
 */
class SttPipelineNode(
    private val sessionId: String,
    private val config: AgentSessionConfig,
    private val db: AppDatabase,
    private val eventSink: AgentEventSink,
    private val onFinalResult: (requestId: String, text: String) -> Unit,
    private val onSpeechStart: () -> Unit = {},
) {
    companion object {
        private const val SAMPLE_RATE = 16000
        private const val TAG = "SttPipelineNode"
    }

    private var isListening = false
    private var recognizer: SpeechRecognizer? = null
    private var speechConfig: SpeechConfig? = null
    private var audioRecord: AudioRecord? = null
    private var pushStream: PushAudioInputStream? = null
    private var aec: AcousticEchoCanceler? = null
    private var ns: NoiseSuppressor? = null
    private var pumpJob: Job? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private fun setup() {
        if (recognizer != null) return
        if (!config.sttPluginName.startsWith("stt_azure")) return

        try {
            val cfg = JSONObject(config.sttConfigJson)
            val apiKey = cfg.optString("apiKey")
            val region = cfg.optString("region")
            val language = cfg.optString("language").ifBlank { "zh-CN" }

            if (apiKey.isBlank() || region.isBlank()) {
                Log.w(TAG, "apiKey or region is blank, STT disabled")
                return
            }

            // ── 1. AudioRecord with VOICE_COMMUNICATION (enables hardware AEC reference) ──
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

            // ── 2. Attach AEC + NoiseSuppressor ──
            val sessionId = ar.audioSessionId
            if (AcousticEchoCanceler.isAvailable()) {
                aec = AcousticEchoCanceler.create(sessionId)?.also { it.enabled = true }
                Log.d(TAG, "AcousticEchoCanceler enabled=${aec?.enabled}")
            } else {
                Log.w(TAG, "AcousticEchoCanceler not available on this device")
            }
            if (NoiseSuppressor.isAvailable()) {
                ns = NoiseSuppressor.create(sessionId)?.also { it.enabled = true }
                Log.d(TAG, "NoiseSuppressor enabled=${ns?.enabled}")
            }

            // ── 3. PushAudioInputStream → Azure AudioConfig ──
            val format = AudioStreamFormat.getWaveFormatPCM(SAMPLE_RATE.toLong(), 16, 1)
            val ps = AudioInputStream.createPushStream(format)
            pushStream = ps

            val audioConfig = AudioConfig.fromStreamInput(ps)

            // ── 4. SpeechRecognizer ──
            speechConfig = SpeechConfig.fromSubscription(apiKey, region).apply {
                speechRecognitionLanguage = language
            }

            recognizer = SpeechRecognizer(speechConfig, audioConfig).apply {
                recognizing.addEventListener { _, e ->
                    if (e.result.text.isNotBlank()) {
                        pushEvent(SttEventData(this@SttPipelineNode.sessionId,
                            requestId = "", kind = "partialResult", text = e.result.text))
                    }
                }
                recognized.addEventListener { _, e ->
                    if (e.result.reason == ResultReason.RecognizedSpeech && e.result.text.isNotBlank()) {
                        val reqId = UUID.randomUUID().toString()
                        pushEvent(SttEventData(this@SttPipelineNode.sessionId,
                            requestId = reqId, kind = "finalResult", text = e.result.text))
                        onFinalResult(reqId, e.result.text)
                    }
                }
                speechStartDetected.addEventListener { _, _ ->
                    pushEvent(SttEventData(this@SttPipelineNode.sessionId,
                        requestId = "", kind = "vadSpeechStart"))
                    onSpeechStart()
                }
                speechEndDetected.addEventListener { _, _ ->
                    pushEvent(SttEventData(this@SttPipelineNode.sessionId,
                        requestId = "", kind = "vadSpeechEnd"))
                }
                sessionStopped.addEventListener { _, _ ->
                    pushEvent(SttEventData(this@SttPipelineNode.sessionId,
                        requestId = "", kind = "listeningStopped"))
                }
                canceled.addEventListener { _, e ->
                    if (e.reason == CancellationReason.Error) {
                        pushEvent(SttEventData(this@SttPipelineNode.sessionId,
                            requestId = "", kind = "error",
                            errorCode = e.errorCode.toString(), errorMessage = e.errorDetails))
                    }
                }
            }
            Log.d(TAG, "SpeechRecognizer created: region=$region lang=$language AEC=${aec != null}")
        } catch (e: Exception) {
            Log.e(TAG, "setup failed: ${e.message}")
        }
    }

    suspend fun startListening() {
        if (isListening) return
        isListening = true
        pushEvent(SttEventData(sessionId, requestId = "", kind = "listeningStarted"))

        withContext(Dispatchers.IO) {
            setup()
            val ar = audioRecord ?: return@withContext
            val ps = pushStream ?: return@withContext

            try {
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

                recognizer?.startContinuousRecognitionAsync()?.get()
                Log.d(TAG, "Continuous recognition started")
            } catch (e: Exception) {
                Log.e(TAG, "startListening failed: ${e.message}")
                pushEvent(SttEventData(sessionId, requestId = "", kind = "error",
                    errorCode = "stt_start_error", errorMessage = e.message))
            }
        }
    }

    suspend fun stopListening() {
        isListening = false
        val hadRecognizer = recognizer != null
        withContext(Dispatchers.IO) {
            try {
                recognizer?.stopContinuousRecognitionAsync()?.get()
            } catch (e: Exception) {
                Log.e(TAG, "stopContinuousRecognitionAsync failed: ${e.message}")
            }
            pumpJob?.cancel()
            pumpJob = null
            runCatching { audioRecord?.stop() }
        }
        // sessionStopped listener already fires listeningStopped when recognizer is configured;
        // only push manually as fallback when STT is not set up.
        if (!hadRecognizer) {
            pushEvent(SttEventData(sessionId, requestId = "", kind = "listeningStopped"))
        }
    }

    fun release() {
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
    }

    private fun pushEvent(event: SttEventData) {
        eventSink.onSttEvent(event)
    }
}
