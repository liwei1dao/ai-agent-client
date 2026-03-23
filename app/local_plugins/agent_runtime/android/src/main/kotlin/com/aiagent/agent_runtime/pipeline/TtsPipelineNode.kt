package com.aiagent.agent_runtime.pipeline

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.util.Log
import com.aiagent.agent_runtime.*
import kotlinx.coroutines.*
import okhttp3.Call
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.File
import java.io.IOException

/**
 * TtsPipelineNode — 调用 Azure TTS REST API 合成，用 MediaPlayer 播放
 *
 * 打断机制：
 *   - AgentSession 取消 activeJob 时，withContext/await 会传播 CancellationException
 *   - finally 块负责停止并释放 MediaPlayer
 */
class TtsPipelineNode(
    private val sessionId: String,
    private val config: AgentSessionConfig,
    private val eventSink: AgentEventSink,
    private val context: Context,
) {
    private val client = OkHttpClient()
    @Volatile private var activeCall: Call? = null
    @Volatile private var activePlayer: MediaPlayer? = null
    @Volatile private var playbackDeferred: CompletableDeferred<Unit>? = null

    suspend fun speak(requestId: String, text: String) {
        try {
            if (!config.ttsPluginName.startsWith("tts_azure")) return
            if (text.isBlank()) return

            val cfg = JSONObject(config.ttsConfigJson)
            val apiKey = cfg.optString("apiKey")
            val region = cfg.optString("region")
            val voice = cfg.optString("voiceName").ifBlank { "zh-CN-XiaoxiaoNeural" }

            if (apiKey.isBlank() || region.isBlank()) {
                Log.w("TtsPipelineNode", "apiKey or region is blank, TTS skipped")
                return
            }

            pushTtsEvent(TtsEventData(sessionId, requestId, kind = "synthesisStart"))

            // ── 1. Azure TTS REST API ─────────────────────────────────────────────────
            val ssml = "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='zh-CN'>" +
                    "<voice name='$voice'>$text</voice></speak>"

            val audioBytes = withContext(Dispatchers.IO) {
                val call = client.newCall(
                    Request.Builder()
                        .url("https://$region.tts.speech.microsoft.com/cognitiveservices/v1")
                        .post(ssml.toRequestBody("application/ssml+xml".toMediaType()))
                        .header("Ocp-Apim-Subscription-Key", apiKey)
                        .header("X-Microsoft-OutputFormat", "audio-16khz-128kbitrate-mono-mp3")
                        .build()
                )
                activeCall = call
                try {
                    val response = call.execute()
                    if (!response.isSuccessful) {
                        throw IOException("TTS HTTP ${response.code}: ${response.message}")
                    }
                    response.body?.bytes() ?: throw IOException("TTS empty body")
                } finally {
                    activeCall = null
                }
            }

            pushTtsEvent(TtsEventData(sessionId, requestId, kind = "synthesisReady"))
            pushTtsEvent(TtsEventData(sessionId, requestId, kind = "playbackStart"))

            // ── 2. 写临时文件，MediaPlayer 播放 ─────────────────────────────────────
            val tmpFile = withContext(Dispatchers.IO) {
                File.createTempFile("tts_", ".mp3", context.cacheDir).also { it.writeBytes(audioBytes) }
            }

            try {
                withContext(Dispatchers.Main) {
                    val done = CompletableDeferred<Unit>()
                    playbackDeferred = done
                    val player = MediaPlayer()
                    activePlayer = player
                    try {
                        // 使用 VOICE_CALL 流，让系统 AEC 能获取参考信号
                        player.setAudioAttributes(
                            AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                                .build()
                        )
                        player.setDataSource(tmpFile.absolutePath)
                        player.setOnPreparedListener { it.start() }
                        player.setOnCompletionListener { done.complete(Unit) }
                        player.setOnErrorListener { _, what, extra ->
                            done.completeExceptionally(IOException("MediaPlayer error $what/$extra"))
                            true
                        }
                        player.prepareAsync()
                        done.await()
                    } finally {
                        playbackDeferred = null
                        activePlayer = null
                        runCatching { player.stop() }
                        runCatching { player.release() }
                    }
                }
            } finally {
                tmpFile.delete()
            }

            pushTtsEvent(TtsEventData(sessionId, requestId, kind = "playbackDone"))

        } catch (e: CancellationException) {
            pushTtsEvent(TtsEventData(sessionId, requestId, kind = "playbackInterrupted"))
            throw e  // 重新抛出让协程正常取消
        } catch (e: Exception) {
            Log.e("TtsPipelineNode", "speak failed: ${e.message}")
            pushTtsEvent(TtsEventData(
                sessionId, requestId, kind = "error",
                errorCode = "tts_error", errorMessage = e.message,
            ))
        }
    }

    /** 立即打断：取消 HTTP + 完成 deferred（让 done.await() 解锁），MediaPlayer 由 finally 块在主线程清理 */
    fun interrupt() {
        activeCall?.cancel()
        playbackDeferred?.cancel(CancellationException("voice_interrupt"))
    }

    fun release() { interrupt() }

    private fun pushTtsEvent(event: TtsEventData) {
        eventSink.onTtsEvent(event)
    }
}
