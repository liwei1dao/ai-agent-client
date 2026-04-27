package com.aiagent.tts_azure

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.util.Log
import com.aiagent.plugin_interface.AudioOutputManager
import com.aiagent.plugin_interface.NativeTtsService
import com.aiagent.plugin_interface.TtsAudio
import com.aiagent.plugin_interface.TtsCallback
import kotlinx.coroutines.*
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.util.Collections

/**
 * TtsAzureService — Azure TTS 原生服务实现
 *
 * 双步暴露：
 *   - synthesize(text) → TtsAudio：HTTP REST，返回 mp3 字节；支持并发调用
 *   - play(audio)：写临时文件 + MediaPlayer 播放；串行调用
 *
 * 上层（agent_chat / agent_translate）按 §4.1 做"合成节流(≤2) + 播放队列(FIFO)"，
 * 实现"边播边合成"，本类不再耦合两步。
 */
class TtsAzureService(private val appContext: Context) : NativeTtsService {

    companion object {
        private const val TAG = "TtsAzureService"
    }

    private val client = OkHttpClient()

    /** 正在进行的合成请求（synthesize 可并发） */
    private val activeCalls: MutableSet<Call> = Collections.synchronizedSet(mutableSetOf())

    /** 正在播放的 player（play 必须串行） */
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

    override suspend fun synthesize(requestId: String, text: String): TtsAudio {
        require(text.isNotBlank()) { "synthesize text is blank" }
        if (apiKey.isBlank() || region.isBlank()) {
            throw IOException("tts.config_missing: apiKey or region is blank")
        }

        val ssml = "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='zh-CN'>" +
                "<voice name='$voiceName'>${escapeXml(text)}</voice></speak>"

        val request = Request.Builder()
            .url("https://$region.tts.speech.microsoft.com/cognitiveservices/v1")
            .post(ssml.toRequestBody("application/ssml+xml".toMediaType()))
            .header("Ocp-Apim-Subscription-Key", apiKey)
            .header("X-Microsoft-OutputFormat", "audio-16khz-128kbitrate-mono-mp3")
            .build()

        val call = client.newCall(request)
        activeCalls.add(call)
        return try {
            val bytes = suspendCancellableCoroutine<ByteArray> { cont ->
                cont.invokeOnCancellation { call.cancel() }
                call.enqueue(object : Callback {
                    override fun onFailure(c: Call, e: IOException) {
                        if (cont.isActive) cont.resumeWith(Result.failure(e))
                    }
                    override fun onResponse(c: Call, response: Response) {
                        try {
                            response.use { r ->
                                if (!r.isSuccessful) {
                                    cont.resumeWith(Result.failure(
                                        IOException("TTS HTTP ${r.code}: ${r.message}")
                                    ))
                                    return
                                }
                                val body = r.body?.bytes()
                                    ?: throw IOException("TTS empty body")
                                cont.resumeWith(Result.success(body))
                            }
                        } catch (e: Throwable) {
                            if (cont.isActive) cont.resumeWith(Result.failure(e))
                        }
                    }
                })
            }
            TtsAudio(data = bytes, format = "mp3", durationMs = null)
        } finally {
            activeCalls.remove(call)
        }
    }

    override suspend fun play(requestId: String, audio: TtsAudio, callback: TtsCallback) {
        if (audio.data.isEmpty()) return

        val tmpFile = withContext(Dispatchers.IO) {
            File.createTempFile("tts_", ".${audio.format}", appContext.cacheDir)
                .also { it.writeBytes(audio.data) }
        }

        try {
            withContext(Dispatchers.Main) {
                val done = CompletableDeferred<Unit>()
                playbackDeferred = done
                val player = MediaPlayer()
                activePlayer = player
                try {
                    AudioOutputManager.applyMode()

                    // USAGE_VOICE_COMMUNICATION 让系统 AEC 拿到参考信号
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
                    try {
                        done.await()
                    } catch (e: CancellationException) {
                        callback.onPlaybackInterrupted()
                        throw e
                    }
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
    }

    override fun stop() {
        // 取消所有进行中的合成请求
        synchronized(activeCalls) {
            activeCalls.forEach { runCatching { it.cancel() } }
        }
        // 取消当前播放
        playbackDeferred?.cancel(CancellationException("tts_stop"))
    }

    override fun release() {
        stop()
    }

    private fun escapeXml(s: String): String =
        s.replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace("\"", "&quot;")
            .replace("'", "&apos;")
}
