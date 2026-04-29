package com.aiagent.tts_azure

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.util.Log
import com.aiagent.plugin_interface.AudioOutputManager
import com.aiagent.plugin_interface.ExternalAudioCapability
import com.aiagent.plugin_interface.ExternalAudioFormat
import com.aiagent.plugin_interface.ExternalAudioFrame
import com.aiagent.plugin_interface.ExternalAudioSink
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

        /** 外部音频协商格式：PCM_S16LE / 16kHz / mono / 20ms = 640 bytes / frame */
        private const val EXT_SAMPLE_RATE = 16000
        private const val EXT_FRAME_MS = 20
        private const val EXT_FRAME_BYTES = EXT_SAMPLE_RATE * 2 * EXT_FRAME_MS / 1000  // 640
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

    /** 外部音频模式：合成走 raw PCM，play 把 PCM 切帧回灌 sink。与本地播放互斥。 */
    @Volatile private var externalMode = false
    @Volatile private var externalSink: ExternalAudioSink? = null

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

        // 外部模式拿原始 PCM（无 RIFF header），便于切帧灌入 sink；
        // 本地播放走 mp3 由 MediaPlayer 解码。
        val outputFormat = if (externalMode) "raw-16khz-16bit-mono-pcm"
            else "audio-16khz-128kbitrate-mono-mp3"

        val request = Request.Builder()
            .url("https://$region.tts.speech.microsoft.com/cognitiveservices/v1")
            .post(ssml.toRequestBody("application/ssml+xml".toMediaType()))
            .header("Ocp-Apim-Subscription-Key", apiKey)
            .header("X-Microsoft-OutputFormat", outputFormat)
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
            val format = if (externalMode) "pcm16" else "mp3"
            val durationMs = if (externalMode) {
                // PCM_S16LE 16kHz mono: 32 bytes per ms
                (bytes.size / 32)
            } else null
            TtsAudio(data = bytes, format = format, durationMs = durationMs)
        } finally {
            activeCalls.remove(call)
        }
    }

    override suspend fun play(requestId: String, audio: TtsAudio, callback: TtsCallback) {
        if (audio.data.isEmpty()) return

        // 外部模式：切帧灌入 sink，不走 MediaPlayer。
        if (externalMode) {
            playToExternalSink(audio, callback)
            return
        }

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
        externalMode = false
        externalSink = null
    }

    // ─────────────────────────────────────────────────
    // 外部音频源（通话翻译等场景）
    // ─────────────────────────────────────────────────

    override fun externalAudioCapability(): ExternalAudioCapability =
        ExternalAudioCapability(
            acceptsOpus = false,
            acceptsPcm = true,
            preferredSampleRate = EXT_SAMPLE_RATE,
            preferredChannels = 1,
            preferredFrameMs = EXT_FRAME_MS,
        )

    override fun startExternalAudio(format: ExternalAudioFormat, sink: ExternalAudioSink) {
        if (format.codec != ExternalAudioFormat.Codec.PCM_S16LE) {
            throw IllegalArgumentException(
                "tts_azure accepts only PCM_S16LE (got ${format.codec})")
        }
        if (format.sampleRate != EXT_SAMPLE_RATE || format.channels != 1) {
            throw IllegalArgumentException(
                "tts_azure requires ${EXT_SAMPLE_RATE}Hz mono " +
                    "(got ${format.sampleRate}Hz/${format.channels}ch)")
        }
        externalSink = sink
        externalMode = true
        Log.d(TAG, "startExternalAudio: PCM_S16LE ${format.sampleRate}Hz mono ${format.frameMs}ms")
    }

    override fun stopExternalAudio() {
        if (!externalMode) return
        externalMode = false
        externalSink = null
        Log.d(TAG, "stopExternalAudio")
    }

    /**
     * 外部模式下的播放：把 PCM 字节按 20ms 一帧切片送入 sink，**不再做 frame 间 delay**。
     *
     * 历史：之前每帧 delay(20ms) 模拟实时节奏，理由是"让设备端缓冲压力小"。
     * 但 Azure TTS 是**整段返回**（不是流式合成）的 PCM —— 这种 delay 只起一个负作用：
     * 把段末 [ExternalAudioFrame.isFinal] = true 的到达时间往后拖整整 (帧数 × 20ms)。
     * 下游 (runtime / 编排器) 必须等 isFinal 才能触发整段下发（杰理通话翻译），延迟随译文
     * 长度线性累加，对方耳机听到的声音会越积越晚。
     *
     * 现在：分片协议形态保留（与 STS/AST 流式服务一致：多帧 + 末帧 isFinal=true），但本服务
     * 的整段 PCM 已经在内存里，没必要按"实时速率"喂——直接连续推完。
     * STS/AST 路径不受影响，那边的节奏是 websocket 自身控制的，本就不依赖此 delay。
     */
    private suspend fun playToExternalSink(audio: TtsAudio, callback: TtsCallback) {
        val sink = externalSink ?: run {
            callback.onError("tts_no_sink", "external mode active but sink is null")
            return
        }
        if (audio.format != "pcm16") {
            callback.onError("tts_format", "external mode requires pcm16 (got ${audio.format})")
            return
        }
        val data = audio.data
        val total = data.size
        val done = CompletableDeferred<Unit>()
        playbackDeferred = done

        try {
            withContext(Dispatchers.IO) {
                var offset = 0
                while (offset < total) {
                    if (!isActive) break
                    val chunkLen = minOf(EXT_FRAME_BYTES, total - offset)
                    val chunk = data.copyOfRange(offset, offset + chunkLen)
                    val isLast = offset + chunkLen >= total
                    sink.onTtsFrame(
                        ExternalAudioFrame(
                            codec = ExternalAudioFormat.Codec.PCM_S16LE,
                            sampleRate = EXT_SAMPLE_RATE,
                            channels = 1,
                            bytes = chunk,
                            isFinal = isLast,
                        )
                    )
                    offset += chunkLen
                }
                done.complete(Unit)
            }
            done.await()
        } catch (e: CancellationException) {
            callback.onPlaybackInterrupted()
            throw e
        } finally {
            playbackDeferred = null
        }
    }

    private fun escapeXml(s: String): String =
        s.replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace("\"", "&quot;")
            .replace("'", "&apos;")
}
