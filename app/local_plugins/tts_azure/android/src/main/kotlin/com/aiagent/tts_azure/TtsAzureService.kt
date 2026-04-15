package com.aiagent.tts_azure

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.util.Log
import com.aiagent.plugin_interface.AudioOutputManager
import com.aiagent.plugin_interface.NativeTtsService
import com.aiagent.plugin_interface.TtsCallback
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
 * TtsAzureService — Azure TTS 原生服务实现
 *
 * 实现 NativeTtsService 接口，供 Agent 类型插件直接调用。
 *
 * 合入原 TtsPipelineNode 的全部逻辑：
 * - Azure TTS REST API（SSML → MP3）
 * - MediaPlayer 播放（USAGE_VOICE_COMMUNICATION，让 AEC 获取参考信号）
 * - 打断机制：cancel HTTP + cancel deferred
 */
class TtsAzureService(private val appContext: Context) : NativeTtsService {

    companion object {
        private const val TAG = "TtsAzureService"
    }

    private val client = OkHttpClient()
    @Volatile private var activeCall: Call? = null
    @Volatile private var activePlayer: MediaPlayer? = null
    @Volatile private var playbackDeferred: CompletableDeferred<Unit>? = null

    private var apiKey: String = ""
    private var region: String = ""
    private var voiceName: String = "zh-CN-XiaoxiaoNeural"

    // ─────────────────────────────────────────────────
    // NativeTtsService 接口实现
    // ─────────────────────────────────────────────────

    override fun initialize(configJson: String, context: Context) {
        val cfg = JSONObject(configJson)
        apiKey = cfg.optString("apiKey", "")
        region = cfg.optString("region", "")
        voiceName = cfg.optString("voiceName", "zh-CN-XiaoxiaoNeural").ifBlank { "zh-CN-XiaoxiaoNeural" }
        Log.d(TAG, "initialize: region=$region voiceName=$voiceName")
    }

    override suspend fun speak(requestId: String, text: String, callback: TtsCallback) {
        try {
            if (text.isBlank()) return
            if (apiKey.isBlank() || region.isBlank()) {
                Log.w(TAG, "apiKey or region is blank, TTS skipped")
                return
            }

            callback.onSynthesisStart()

            // 1. Azure TTS REST API
            val ssml = "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='zh-CN'>" +
                    "<voice name='$voiceName'>$text</voice></speak>"

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

            callback.onSynthesisReady(0)
            callback.onPlaybackStart()

            // 2. Write temp file, MediaPlayer playback
            val tmpFile = withContext(Dispatchers.IO) {
                File.createTempFile("tts_", ".mp3", appContext.cacheDir).also { it.writeBytes(audioBytes) }
            }

            try {
                withContext(Dispatchers.Main) {
                    val done = CompletableDeferred<Unit>()
                    playbackDeferred = done
                    val player = MediaPlayer()
                    activePlayer = player
                    try {
                        // 在播放前应用音频输出路由设置
                        AudioOutputManager.applyMode()

                        // USAGE_VOICE_COMMUNICATION lets system AEC get reference signal
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

            callback.onPlaybackDone()

        } catch (e: CancellationException) {
            callback.onPlaybackInterrupted()
            throw e
        } catch (e: Exception) {
            Log.e(TAG, "speak failed: ${e.message}")
            callback.onError("tts_error", e.message ?: "Unknown error")
        }
    }

    override fun stop() {
        activeCall?.cancel()
        playbackDeferred?.cancel(CancellationException("tts_stop"))
    }

    override fun release() {
        stop()
    }
}
