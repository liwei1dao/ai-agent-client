package com.aiagent.ast_volcengine

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.NoiseSuppressor
import android.util.Log
import com.aiagent.plugin_interface.AstCallback
import com.aiagent.plugin_interface.AstRole
import com.aiagent.plugin_interface.AudioOutputManager
import com.aiagent.plugin_interface.ExternalAudioCapability
import com.aiagent.plugin_interface.ExternalAudioFormat
import com.aiagent.plugin_interface.ExternalAudioFrame
import com.aiagent.plugin_interface.ExternalAudioSink
import com.aiagent.plugin_interface.NativeAstService
import kotlinx.coroutines.*
import okhttp3.*
import okio.ByteString
import okio.ByteString.Companion.toByteString
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.util.UUID
import java.util.concurrent.ThreadLocalRandom
import java.util.concurrent.TimeUnit

/**
 * AstVolcengineService — 火山引擎端到端语音翻译（AST）
 *
 * 协议：纯 Protobuf 二进制（无自定义帧头）
 *   WebSocket  wss://openspeech.bytedance.com/api/v4/ast/v2/translate
 *
 * 流程：
 *   1. 连接 WebSocket（X-Api-App-Key=appId, X-Api-Access-Key=token）
 *   2. 发送 StartSession(event=100) Protobuf -> 收到 SessionStarted(event=150)
 *   3. 持续发送 TaskRequest(event=200) PCM 音频帧
 *   4. 收到 SourceSubtitleResponse(651) -> 用户原始语音文字
 *      收到 TranslationSubtitleResponse(654) -> 翻译文字
 *      音频数据附在 TranslationSubtitleResponse.data 字段 -> 写入 AudioTrack
 *   5. 发送 FinishSession(event=102) -> 收到 SessionFinished(152)
 *
 * Auth：
 *   - X-Api-App-Key = 用户 appKey
 *   - X-Api-Resource-Id = "volc.bigasr.auc"（固定）
 */
class AstVolcengineService(private val appContext: Context) : NativeAstService {

    companion object {
        private const val TAG = "AstVolcengine"
        private const val MIC_SAMPLE_RATE  = 16000          // 麦克风采样率
        private const val TTS_SAMPLE_RATE  = 24000          // 服务端 TTS 输出采样率
        private const val FRAME_BYTES      = 3200           // 100ms @ 16kHz 16-bit mono
        private const val VOLUME_GAIN      = 3.0f           // 软件增益倍数（服务端返回音量偏小）
        private const val WS_URL = "wss://openspeech.bytedance.com/api/v4/ast/v2/translate"
        private const val FIXED_RESOURCE_ID = "volc.bigasr.auc"

        // ─── 火山 AST 协议事件码（Type enum，from events.proto）─────────────────
        //
        // 编号区段语义：
        //   100~199  会话生命周期（client → server 用 1xx 偶数；server → client 用 1xx 奇数附近）
        //   200~299  音频任务请求（client → server）
        //   300~399  TTS 合成相关（server → client，端到端模式下伴随音频字节）
        //   400~499  ASR 实时识别（server → client）
        //   600~699  字幕事件（server → client）：源语言 65x，译文 65x（START/SUBTITLE/END 三件套）
        //
        // 一轮"一句话"的标准事件序列（端到端 mode=s2s）：
        //   client → 100 StartSession
        //   server ← 150 SessionStarted
        //   client → 200 TaskRequest（持续推 PCM）
        //   server ← 451* 实时 ASR 预览（可选）
        //   server ← 650 → 651* → 652   源语言字幕一句完整（START → 增量 → END）
        //   server ← 653 → 654* → 655   译文字幕一句完整（音频字节附在 654.data 字段）
        //   server ← 350* → 359         TTS 句首/句尾（部分场景才发；用作段尾兜底信号）
        //   ...（下一句重复 650~655）
        //   client → 102 FinishSession
        //   server ← 152 SessionFinished
        //   异常分支：server ← 153 SessionFailed（带错误码，stream 终止）
        //   server ← 154 UsageResponse（计费用量回执，可忽略）

        // ── 会话生命周期 ──
        /** client → server：开启会话，payload 含 user / source_audio / target_audio / mode 等。 */
        private const val EVT_START_SESSION    = 100
        /** client → server：主动结束会话；服务端会回 [EVT_SESSION_FINISHED]。 */
        private const val EVT_FINISH_SESSION   = 102
        /** server → client：StartSession 已被服务端接受，可以开始推音频。 */
        private const val EVT_SESSION_STARTED  = 150
        /** server → client：会话正常结束（FinishSession 应答）。 */
        private const val EVT_SESSION_FINISHED = 152
        /** server → client：会话失败（鉴权 / 配额 / 8s 无音频 timeout 等）；带 status + msg。 */
        private const val EVT_SESSION_FAILED   = 153
        /** server → client：用量回执（计费维度，业务无需消费）。 */
        private const val EVT_USAGE_RESPONSE   = 154

        // ── 音频上行 ──
        /** client → server：单帧 PCM 任务请求；source_audio.binary_data 字段携带音频字节。 */
        private const val EVT_TASK_REQUEST     = 200

        // ── TTS 合成（端到端 s2s 模式下，音频字节嵌在 65x.data；35x 仅作段边界提示）──
        /** server → client：TTS 句首事件，data 字段可能携带首段音频 PCM。 */
        private const val EVT_TTS_SENTENCE_START = 350
        /** server → client：TTS 整句合成完毕；上层据此发 isFinal=true 让下游 flush。 */
        private const val EVT_TTS_ENDED        = 359

        // ── ASR 实时识别（中间预览，不一定每轮都发）──
        /** server → client：实时 ASR 部分结果 / 增量文本（s2s 模式下偶发）。 */
        private const val EVT_ASR_RESPONSE     = 451

        // ── 源语言字幕（说话人原文）──
        /** server → client：源语言字幕开始；标记本句新轮次的起点。 */
        private const val EVT_SRC_SUBTITLE_START = 650
        /** server → client：源语言字幕**增量片段**（需在客户端累积成完整句）。 */
        private const val EVT_SRC_SUBTITLE     = 651
        /** server → client：源语言字幕结束；本句源文已全部送达，等待译文。 */
        private const val EVT_SRC_SUBTITLE_END = 652

        // ── 译文字幕（带 TTS 音频）──
        /** server → client：译文字幕开始；后续 654 帧的 data 字段会附带 TTS PCM 音频。 */
        private const val EVT_TRANS_SUBTITLE_START = 653
        /** server → client：译文字幕**增量片段** + TTS 音频字节（写入 AudioTrack / sink）。 */
        private const val EVT_TRANS_SUBTITLE   = 654
        /** server → client：译文字幕结束；本轮译文完成，触发下游 flush + endRound。 */
        private const val EVT_TRANS_SUBTITLE_END = 655
    }

    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .writeTimeout(0, TimeUnit.MILLISECONDS)
        .build()

    @Volatile private var webSocket: WebSocket? = null
    @Volatile private var audioRecord: AudioRecord? = null
    @Volatile private var audioTrack: AudioTrack? = null
    @Volatile private var aec: AcousticEchoCanceler? = null
    @Volatile private var ns: NoiseSuppressor? = null
    @Volatile private var isRunning      = false
    @Volatile private var isConnected    = false
    @Volatile private var isAudioRunning = false
    @Volatile private var externalMode   = false
    @Volatile private var externalSink: ExternalAudioSink? = null
    @Volatile private var remoteSessionId: String = ""
    @Volatile private var connectId: String = ""
    @Volatile private var srcLang: String = "zh"
    @Volatile private var dstLang: String = "en"

    // 字幕文本累积器（服务端发送增量片段，需要累积为完整文本）
    private val srcSubtitleAccum = StringBuilder()
    private val transSubtitleAccum = StringBuilder()

    // Recognition round state (mirrors AST 5-piece lifecycle in AstCallback).
    @Volatile private var currentRequestId: String? = null
    @Volatile private var sourceRoleOpen = false
    @Volatile private var translatedRoleOpen = false

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var pumpJob: Job? = null
    private var wsReady        = CompletableDeferred<Unit>()
    private var sessionStarted = CompletableDeferred<Unit>()

    private var callback: AstCallback? = null

    // Config fields parsed from configJson
    private var appKey: String = ""
    private var accessKey: String = ""
    private var resourceId: String = FIXED_RESOURCE_ID

    // ─── NativeAstService Implementation ──────────────────────────────────────────

    override fun initialize(configJson: String, context: Context) {
        val config = JSONObject(configJson)
        appKey = config.optString("appKey").ifBlank { config.optString("appId") }
        accessKey = config.optString("accessKey").ifBlank { config.optString("accessToken") }
        resourceId = config.optString("resourceId").ifBlank { FIXED_RESOURCE_ID }
        // 火山 AST 协议只认短码（zh / en / ja …），不认 BCP-47 完整 locale
        // （zh-CN / en-US / ja-JP）—— 不归一化会得到 status=45000001
        // "InvalidData:sp ... langPair:zh-CN2en-US not found"。
        // 调用方（agent / 服务测试 / call_translate）传什么都接住，由本插件归一。
        srcLang = normalizeLang(config.optString("srcLang"))
        dstLang = normalizeLang(config.optString("dstLang"))
        Log.d(TAG, "initialize: appKey=${appKey.take(8)}... srcLang=$srcLang dstLang=$dstLang")
    }

    private fun normalizeLang(raw: String): String {
        val s = raw.trim()
        if (s.isEmpty()) return "zh"
        // 取 BCP-47 primary subtag：zh-CN → zh, en_US → en, ja-JP → ja
        return s.substringBefore('-').substringBefore('_').lowercase()
    }

    override fun connect(callback: AstCallback) {
        this.callback = callback

        if (appKey.isBlank() || accessKey.isBlank()) {
            Log.e(TAG, "AST config missing: appKey=${appKey.isBlank()} accessKey=${accessKey.isBlank()}")
            callback.onError("config_error", "appKey or accessKey missing")
            return
        }

        scope.launch {
            try {
                isRunning = true
                remoteSessionId = UUID.randomUUID().toString()
                connectId = UUID.randomUUID().toString()
                srcSubtitleAccum.clear()
                transSubtitleAccum.clear()

                Log.d(TAG, "connect(): appKey='${appKey}'(len=${appKey.length}) accessKey='${accessKey.take(8)}...'(len=${accessKey.length}) resourceId='$resourceId' srcLang=$srcLang dstLang=$dstLang url=$WS_URL")

                // 注意：connect() 阶段**不**碰本地音频硬件。
                // setupAudioRecord / setupAudioTrack 会触发
                // AudioManager.MODE_IN_COMMUNICATION + clearCommunicationDevice，
                // 把系统蓝牙 SCO 通道抢走，与 call-translation external audio 模式
                // 下 jieli RCSP MODE_CALL_TRANSLATION 互斥；耳机推不上 OPUS 翻译帧。
                // 因此把硬件初始化推迟到 startAudio()（仅 self-mic 模式调用）。

                wsReady        = CompletableDeferred()
                sessionStarted = CompletableDeferred()

                val request = Request.Builder()
                    .url(WS_URL)
                    .header("X-Api-App-Key",     appKey)
                    .header("X-Api-Access-Key",  accessKey)
                    .header("X-Api-Resource-Id", resourceId)
                    .header("X-Api-Connect-Id",  connectId)
                    .build()

                webSocket = client.newWebSocket(request, createListener())

                withTimeout(15_000) { wsReady.await() }
                Log.d(TAG, "WS connected, sending StartSession sid=$remoteSessionId")

                sendProto(buildTranslateRequest(EVT_START_SESSION))
                withTimeout(10_000) { sessionStarted.await() }
                Log.d(TAG, "SessionStarted — ready, waiting for startAudio()")

                isConnected = true
                resetRoundState()
                callback.onConnected()

            } catch (e: CancellationException) {
                isRunning = false
                isConnected = false
                throw e
            } catch (e: Exception) {
                Log.e(TAG, "AST connect failed: ${e.message}", e)
                isRunning = false
                isConnected = false
                callback.onError("ast_error", e.message ?: "unknown")
            }
        }
    }

    override fun startAudio() {
        if (!isConnected || isAudioRunning) {
            Log.d(TAG, "startAudio: skip (connected=$isConnected, audioRunning=$isAudioRunning)")
            return
        }
        if (externalMode) {
            Log.w(TAG, "startAudio: skip (externalMode active — call startExternalAudio path)")
            return
        }
        Log.d(TAG, "startAudio()")
        // self-mic 模式所需的硬件资源：本地 AudioRecord + AEC/NS + AudioTrack。
        // 仅在 startAudio() 这里 lazy 创建，避免在 external-audio 模式下错误地
        // 抢占系统蓝牙 SCO（参见 connect() 注释）。
        if (audioRecord == null) setupAudioRecord()
        if (audioTrack == null) setupAudioTrack()
        // 确保音频输出路由在开始音频前是正确的
        AudioOutputManager.applyMode()
        isAudioRunning = true
        startAudioPump()
    }

    override fun stopAudio() {
        Log.d(TAG, "stopAudio()")
        isAudioRunning = false
        pumpJob?.cancel()
        pumpJob = null
        runCatching { audioRecord?.stop() }
        runCatching { audioTrack?.pause(); audioTrack?.flush(); audioTrack?.play() }
    }

    override fun interrupt() {
        Log.d(TAG, "interrupt() — flush TTS buffer")
        runCatching { audioTrack?.flush() }
    }

    override fun release() {
        Log.d(TAG, "release()")
        stopAudio()
        stopExternalAudio()
        isRunning = false
        isConnected = false
        try { sendProto(buildTranslateRequest(EVT_FINISH_SESSION)) } catch (_: Exception) {}
        try { webSocket?.close(1000, "released") } catch (_: Exception) {}
        webSocket = null
        scope.cancel()
        runCatching { aec?.release() }
        runCatching { ns?.release() }
        runCatching { audioRecord?.release() }
        runCatching { audioTrack?.stop(); audioTrack?.release() }
        audioRecord = null
        audioTrack  = null
        aec = null
        ns  = null
        callback?.onDisconnected()
        callback = null
    }

    // ─── 外部音频源（通话翻译等场景） ─────────────────────────────────────
    //
    // 与 startAudio()/stopAudio() 互斥：通话翻译走 RCSP OPUS → device_jieli native
    // 解码为 PCM → 编排器 push 进来；service 把服务端 TTS PCM 通过 sink 回写，
    // 编排器再调 device 端口灌回耳机。

    override fun externalAudioCapability(): ExternalAudioCapability =
        ExternalAudioCapability(
            acceptsOpus = false,
            acceptsPcm = true,
            preferredSampleRate = MIC_SAMPLE_RATE,
            preferredChannels = 1,
            preferredFrameMs = 20,
        )

    override fun startExternalAudio(format: ExternalAudioFormat, sink: ExternalAudioSink) {
        if (format.codec != ExternalAudioFormat.Codec.PCM_S16LE) {
            throw IllegalArgumentException(
                "ast_volcengine accepts only PCM_S16LE (got ${format.codec}); " +
                    "device side must decode OPUS first")
        }
        if (format.sampleRate != MIC_SAMPLE_RATE || format.channels != 1) {
            throw IllegalArgumentException(
                "ast_volcengine requires ${MIC_SAMPLE_RATE}Hz mono " +
                    "(got ${format.sampleRate}Hz/${format.channels}ch)")
        }
        if (!isConnected) {
            throw IllegalStateException(
                "ast_volcengine not connected; call connect() first")
        }
        if (isAudioRunning) {
            // self-mic 当前在跑（chat UI 默认 'call' 模式会先开 self-mic）；
            // external 路径主动接管：先停 self-mic 再切外部源，避免两个 PCM 源
            // 同时往同一个 WS 灌帧。
            Log.d(TAG, "startExternalAudio: stopping self-mic before takeover")
            stopAudio()
        }
        if (externalMode) {
            Log.d(TAG, "startExternalAudio: already active, replacing sink")
        }
        externalSink = sink
        externalMode = true
        Log.d(TAG, "startExternalAudio: PCM_S16LE ${format.sampleRate}Hz mono ${format.frameMs}ms")
    }

    override fun pushExternalAudioFrame(frame: ByteArray) {
        if (!externalMode || !isConnected || frame.isEmpty()) return
        // 调试：周期性打一次 push 统计，确认 frames 真的发出去了。
        externalPushCount++
        val now = System.currentTimeMillis()
        if (now - externalPushReportMs >= 1000L) {
            Log.d(TAG, "pushExternalAudioFrame stats (last 1s): count=$externalPushCount bytes=${frame.size}")
            externalPushCount = 0
            externalPushReportMs = now
        }
        // 直接走 protobuf TaskRequest；与 startAudioPump 内同样的封包路径。
        sendProto(buildAudioFrame(frame))
    }

    @Volatile private var externalPushCount = 0L
    @Volatile private var externalPushReportMs = 0L

    override fun stopExternalAudio() {
        if (!externalMode) return
        externalMode = false
        externalSink = null
        Log.d(TAG, "stopExternalAudio")
    }

    // ─── Protobuf Encoding ───────────────────────────────────────────────────────

    /**
     * 构建 TranslateRequest Protobuf（与 Python demo 一致：每条消息均携带完整元数据）
     *
     * TranslateRequest fields:
     *   1: request_meta.SessionID (field 6 of RequestMeta)
     *   2: event (varint)
     *   3: user.uid/did
     *   4: source_audio (format/rate/bits/channel + optional binary_data field 14)
     *   5: target_audio (format/rate)
     *   6: request.mode/source_language/target_language
     */
    private fun buildTranslateRequest(event: Int, pcmData: ByteArray? = null): ByteArray {
        val srcAudioFields = run {
            var f = encStr(4, "wav") + encInt(7, 16000) + encInt(8, 16) + encInt(9, 1)
            if (pcmData != null && pcmData.isNotEmpty()) f = f + encBytes(14, pcmData)
            f
        }
        return encMsg(1, encStr(5, connectId) + encStr(6, remoteSessionId)) +
               encEnum(2, event) +
               encMsg(3, encStr(1, "ast_android") + encStr(2, "ast_android")) +
               encMsg(4, srcAudioFields) +
               encMsg(5, encStr(4, "wav") + encInt(7, TTS_SAMPLE_RATE) + encInt(8, 16) + encInt(9, 1)) +
               encMsg(6, encStr(1, "s2s") + encStr(2, srcLang) + encStr(3, dstLang))
    }

    /**
     * 构建仅含音频数据的 TaskRequest（不含冗余元数据，减少带宽开销）
     */
    private fun buildAudioFrame(pcmData: ByteArray): ByteArray {
        return encMsg(1, encStr(6, remoteSessionId)) +
               encEnum(2, EVT_TASK_REQUEST) +
               encMsg(4, encBytes(14, pcmData))
    }

    private fun sendProto(data: ByteArray) {
        webSocket?.send(data.toByteString())
    }

    // ── Protobuf primitive encoders ───────────────────────────────────────────

    private fun varint(value: Long): ByteArray {
        val out = ByteArrayOutputStream()
        var v = value
        while (v and 0x7FL.inv() != 0L) {
            out.write(((v and 0x7F) or 0x80).toInt())
            v = v ushr 7
        }
        out.write(v.toInt())
        return out.toByteArray()
    }

    private fun tag(fieldNum: Int, wireType: Int) = varint((fieldNum.toLong() shl 3) or wireType.toLong())

    // field + varint value (wire type 0)
    private fun encEnum(fieldNum: Int, value: Int): ByteArray {
        if (value == 0) return ByteArray(0)
        return tag(fieldNum, 0) + varint(value.toLong())
    }

    // field + int32 (wire type 0)
    private fun encInt(fieldNum: Int, value: Int): ByteArray {
        if (value == 0) return ByteArray(0)
        return tag(fieldNum, 0) + varint(value.toLong())
    }

    // field + length-delimited string (wire type 2)
    private fun encStr(fieldNum: Int, value: String): ByteArray {
        if (value.isEmpty()) return ByteArray(0)
        val bytes = value.toByteArray(Charsets.UTF_8)
        return tag(fieldNum, 2) + varint(bytes.size.toLong()) + bytes
    }

    // field + length-delimited bytes (wire type 2)
    private fun encBytes(fieldNum: Int, value: ByteArray): ByteArray {
        if (value.isEmpty()) return ByteArray(0)
        return tag(fieldNum, 2) + varint(value.size.toLong()) + value
    }

    // field + length-delimited embedded message (wire type 2)
    private fun encMsg(fieldNum: Int, msg: ByteArray): ByteArray {
        return tag(fieldNum, 2) + varint(msg.size.toLong()) + msg
    }

    // ─── Protobuf Decoding ───────────────────────────────────────────────────────

    private data class PbField(val num: Int, val wireType: Int, val raw: ByteArray)

    private fun decodeProto(bytes: ByteArray): List<PbField> {
        val fields = mutableListOf<PbField>()
        var pos = 0
        while (pos < bytes.size) {
            // read tag varint
            var tag = 0L; var shift = 0
            while (pos < bytes.size) {
                val b = bytes[pos++].toInt() and 0xFF
                tag = tag or ((b and 0x7F).toLong() shl shift); shift += 7
                if (b and 0x80 == 0) break
            }
            val fieldNum  = (tag ushr 3).toInt()
            val wireType  = (tag and 7L).toInt()
            when (wireType) {
                0 -> {
                    var v = 0L; var sh = 0
                    while (pos < bytes.size) {
                        val b = bytes[pos++].toInt() and 0xFF
                        v = v or ((b and 0x7F).toLong() shl sh); sh += 7
                        if (b and 0x80 == 0) break
                    }
                    // Store varint as 8-byte little-endian
                    val vb = ByteArray(8) { i -> (v ushr (i * 8)).toByte() }
                    fields.add(PbField(fieldNum, wireType, vb))
                }
                2 -> {
                    var len = 0L; var sh = 0
                    while (pos < bytes.size) {
                        val b = bytes[pos++].toInt() and 0xFF
                        len = len or ((b and 0x7F).toLong() shl sh); sh += 7
                        if (b and 0x80 == 0) break
                    }
                    val end = minOf(pos + len.toInt(), bytes.size)
                    fields.add(PbField(fieldNum, wireType, bytes.copyOfRange(pos, end)))
                    pos += len.toInt()
                }
                1 -> { pos += 8 }   // 64-bit fixed, skip
                5 -> { pos += 4 }   // 32-bit fixed, skip
                else -> break
            }
        }
        return fields
    }

    private fun fieldLong(fields: List<PbField>, num: Int): Long {
        val f = fields.firstOrNull { it.num == num && it.wireType == 0 } ?: return 0L
        var v = 0L
        for (i in 0 until minOf(8, f.raw.size)) v = v or ((f.raw[i].toLong() and 0xFF) shl (i * 8))
        return v
    }

    private fun fieldBytes(fields: List<PbField>, num: Int): ByteArray =
        fields.firstOrNull { it.num == num && it.wireType == 2 }?.raw ?: ByteArray(0)

    private fun fieldStr(fields: List<PbField>, num: Int): String {
        val b = fieldBytes(fields, num)
        return if (b.isEmpty()) "" else String(b, Charsets.UTF_8)
    }

    // ─── Response Handling ───────────────────────────────────────────────────────

    private fun handleResponse(data: ByteArray) {
        val fields    = decodeProto(data)
        val event     = fieldLong(fields, 2).toInt()
        val audioData = fieldBytes(fields, 3)
        val text      = fieldStr(fields, 4)

        val metaBytes  = fieldBytes(fields, 1)
        val metaFields = if (metaBytes.isNotEmpty()) decodeProto(metaBytes) else emptyList()
        val statusCode = fieldLong(metaFields, 3).toInt()
        val message    = fieldStr(metaFields, 4)

        // 一旦本地主动关掉了 WS（webSocket == null），服务端可能仍在发尾包 /
        // 重复 SessionFailed 帧——全部丢弃，避免日志刷屏 + 反复回调上层。
        if (webSocket == null) return

        Log.d(TAG, "RX event=$event status=$statusCode text=\"${text.take(60)}\" audioLen=${audioData.size}")

        when (event) {
            EVT_SESSION_STARTED -> {
                Log.d(TAG, "SessionStarted!")
                sessionStarted.complete(Unit)
            }

            EVT_SESSION_FINISHED -> {
                Log.d(TAG, "SessionFinished")
                isConnected = false
                forceEndRound()
                callback?.onDisconnected()
            }

            EVT_SESSION_FAILED -> {
                val err = "SessionFailed status=$statusCode msg=$message"
                Log.e(TAG, err)
                isConnected = false
                runCatching { sessionStarted.completeExceptionally(Exception(err)) }
                // 立刻关 WS 并把引用置 null —— 后续重复 SessionFailed 帧会被
                // handleResponse 入口的 `webSocket == null` 守卫挡掉，避免刷屏
                // 和反复回调 onError。
                runCatching { webSocket?.close(1000, "session_failed") }
                webSocket = null
                callback?.onError("ast_session_failed", err)
            }

            EVT_ASR_RESPONSE -> {
                // Partial source-language ASR result (real-time preview)
                if (text.isNotBlank()) {
                    Log.d(TAG, "ASR partial text=\"$text\"")
                    val cb = callback
                    if (cb != null) {
                        beginRound(cb)
                        openRole(cb, AstRole.SOURCE)
                        emitRoleText(cb, AstRole.SOURCE, isFinal = false, text = text)
                    }
                }
                if (audioData.isNotEmpty()) writeAudio(audioData)
            }

            EVT_SRC_SUBTITLE_START -> {
                Log.d(TAG, "SourceSubtitleStart")
                // 新一句开始：重置段尾信号 flag，允许本轮再发一次 isFinal=true。
                ttsFinalSentForRound = false
                srcSubtitleAccum.clear()
                val cb = callback
                if (cb != null) {
                    // 火山协议每句先发完整 SRC（START→SUBTITLE→END），再发 TRANS。
                    // 上一轮如果只发了 SRC_END 没等到 TRANS_END，currentRequestId
                    // 还挂着——这里 force=true 强制结束旧轮再开新轮，避免新句的
                    // SRC 跟旧句的残留 requestId 串起来。
                    beginRound(cb, force = true)
                    openRole(cb, AstRole.SOURCE)
                }
                if (audioData.isNotEmpty()) writeAudio(audioData)
            }

            EVT_SRC_SUBTITLE -> {
                // 源语言字幕（增量片段，需要累积）
                if (text.isNotBlank()) {
                    srcSubtitleAccum.append(text)
                    val accumulated = srcSubtitleAccum.toString()
                    Log.d(TAG, "SourceSubtitle text=\"$accumulated\"")
                    val cb = callback
                    if (cb != null) {
                        beginRound(cb)
                        openRole(cb, AstRole.SOURCE)
                        emitRoleText(cb, AstRole.SOURCE, isFinal = false, text = accumulated)
                    }
                }
                if (audioData.isNotEmpty()) writeAudio(audioData)
            }

            EVT_SRC_SUBTITLE_END -> {
                Log.d(TAG, "SourceSubtitleEnd")
                val cb = callback
                if (cb != null) {
                    if (srcSubtitleAccum.isNotEmpty()) {
                        emitRoleText(cb, AstRole.SOURCE, isFinal = true, text = srcSubtitleAccum.toString())
                    }
                    closeRole(cb, AstRole.SOURCE)
                    // 不在这里 endRound —— 必须保留 currentRequestId 让接下来的
                    // TRANS_START/SUBTITLE/END 共用同一 requestId，UI 端 SubtitleAggregator
                    // 才能把源文与译文配到同一行。endRound 由 TRANS_END 触发。
                }
            }

            EVT_TRANS_SUBTITLE_START -> {
                Log.d(TAG, "TranslationSubtitleStart")
                transSubtitleAccum.clear()
                val cb = callback
                if (cb != null) {
                    beginRound(cb)
                    openRole(cb, AstRole.TRANSLATED)
                }
                if (audioData.isNotEmpty()) writeAudio(audioData)
            }

            EVT_TRANS_SUBTITLE -> {
                // 翻译字幕（增量片段，需要累积）+ TTS 音频数据
                if (text.isNotBlank()) {
                    transSubtitleAccum.append(text)
                    val accumulated = transSubtitleAccum.toString()
                    Log.d(TAG, "TranslationSubtitle text=\"$accumulated\"")
                    val cb = callback
                    if (cb != null) {
                        beginRound(cb)
                        openRole(cb, AstRole.TRANSLATED)
                        emitRoleText(cb, AstRole.TRANSLATED, isFinal = false, text = accumulated)
                    }
                }
                if (audioData.isNotEmpty()) writeAudio(audioData)
            }

            EVT_TRANS_SUBTITLE_END -> {
                Log.d(TAG, "TranslationSubtitleEnd")
                val cb = callback
                if (cb != null) {
                    if (transSubtitleAccum.isNotEmpty()) {
                        emitRoleText(cb, AstRole.TRANSLATED, isFinal = true, text = transSubtitleAccum.toString())
                    }
                    closeRole(cb, AstRole.TRANSLATED)
                    maybeEndRound(cb)
                }
                // 段尾信号：本句的 trans 文本和 TTS 音频都到此为止，给下游 sink
                // 一个 isFinal=true 的空帧，杰理那边据此 flush 缓存（不再等更多帧）。
                // 优先用 EVT_TTS_ENDED；若火山没发 TTS_ENDED 就用 TRANS_END 兜底。
                emitTtsFinalOnce("trans_end")
            }

            EVT_TTS_SENTENCE_START -> {
                Log.d(TAG, "TTSSentenceStart")
                if (audioData.isNotEmpty()) writeAudio(audioData)
            }

            EVT_TTS_ENDED -> {
                Log.d(TAG, "TTSEnded")
                emitTtsFinalOnce("tts_ended")
            }

            EVT_USAGE_RESPONSE -> {
                Log.d(TAG, "UsageResponse")
            }

            else -> {
                if (audioData.isNotEmpty()) writeAudio(audioData)
                if (event != 0) Log.d(TAG, "Unhandled event=$event")
            }
        }
    }

    // ─── Recognition round state machine ──────────────────────────────────────

    private fun beginRound(cb: AstCallback, force: Boolean = false) {
        if (currentRequestId != null) {
            if (!force) return
            if (sourceRoleOpen) closeRole(cb, AstRole.SOURCE)
            if (translatedRoleOpen) closeRole(cb, AstRole.TRANSLATED)
            endRound(cb)
        }
        currentRequestId = newRequestId()
    }

    private fun openRole(cb: AstCallback, role: AstRole) {
        val rid = currentRequestId ?: return
        when (role) {
            AstRole.SOURCE -> {
                if (!sourceRoleOpen) {
                    sourceRoleOpen = true
                    cb.onRecognitionStart(role, rid)
                }
            }
            AstRole.TRANSLATED -> {
                if (!translatedRoleOpen) {
                    translatedRoleOpen = true
                    cb.onRecognitionStart(role, rid)
                }
            }
        }
    }

    private fun closeRole(cb: AstCallback, role: AstRole) {
        val rid = currentRequestId ?: return
        when (role) {
            AstRole.SOURCE -> {
                if (sourceRoleOpen) {
                    sourceRoleOpen = false
                    cb.onRecognitionDone(role, rid)
                }
            }
            AstRole.TRANSLATED -> {
                if (translatedRoleOpen) {
                    translatedRoleOpen = false
                    cb.onRecognitionDone(role, rid)
                }
            }
        }
    }

    private fun maybeEndRound(cb: AstCallback) {
        if (sourceRoleOpen || translatedRoleOpen) return
        if (currentRequestId == null) return
        endRound(cb)
    }

    private fun endRound(cb: AstCallback) {
        val rid = currentRequestId ?: return
        cb.onRecognitionEnd(rid)
        resetRoundState()
    }

    private fun forceEndRound() {
        val cb = callback ?: run { resetRoundState(); return }
        if (currentRequestId == null) return
        if (sourceRoleOpen) closeRole(cb, AstRole.SOURCE)
        if (translatedRoleOpen) closeRole(cb, AstRole.TRANSLATED)
        endRound(cb)
    }

    private fun emitRoleText(cb: AstCallback, role: AstRole, isFinal: Boolean, text: String) {
        val rid = currentRequestId ?: return
        if (isFinal) {
            cb.onRecognized(role, rid, text)
        } else {
            cb.onRecognizing(role, rid, text)
        }
    }

    private fun resetRoundState() {
        currentRequestId = null
        sourceRoleOpen = false
        translatedRoleOpen = false
    }

    private fun newRequestId(): String {
        val ms = System.currentTimeMillis()
        val rand = ThreadLocalRandom.current().nextInt(1 shl 30)
            .toString(36).padStart(6, '0')
        return "ast_volcengine_${ms}_$rand"
    }

    // ─── WebSocket Listener ──────────────────────────────────────────────────────

    private fun createListener() = object : WebSocketListener() {

        override fun onOpen(ws: WebSocket, response: Response) {
            Log.d(TAG, "WS onOpen")
            wsReady.complete(Unit)
        }

        override fun onMessage(ws: WebSocket, text: String) {
            Log.w(TAG, "WS <- unexpected text: ${text.take(200)}")
        }

        override fun onMessage(ws: WebSocket, bytes: ByteString) {
            val data = bytes.toByteArray()
            Log.v(TAG, "WS <- binary ${data.size}B")
            try { handleResponse(data) } catch (e: Exception) {
                Log.e(TAG, "handleResponse error: ${e.message}", e)
            }
        }

        override fun onFailure(ws: WebSocket, t: Throwable, response: Response?) {
            val code = response?.code
            val body = runCatching { response?.body?.string() }.getOrNull()
            val logId = response?.header("X-Tt-Logid")
                ?: response?.header("X-Api-Log-Id")
                ?: response?.header("X-Tt-LogID")
            val resHeader = response?.header("X-Api-Resource-Id")
            Log.e(TAG, "WS failure code=$code logId=$logId resourceIdEcho=$resHeader body=${body?.take(500)} err=${t.message}")
            runCatching { wsReady.completeExceptionally(t) }
            runCatching { sessionStarted.completeExceptionally(t) }
            if (isRunning) {
                val detail = buildString {
                    append("WebSocket error ").append(code).append(": ").append(t.message)
                    if (!body.isNullOrBlank()) append(" | body=").append(body.take(300))
                    if (!logId.isNullOrBlank()) append(" | logId=").append(logId)
                }
                callback?.onError("ws_error", detail)
            }
            isRunning = false
            isConnected = false
            isAudioRunning = false
        }

        override fun onClosing(ws: WebSocket, code: Int, reason: String) {
            Log.d(TAG, "WS onClosing $code $reason")
            ws.close(1000, null)
        }

        override fun onClosed(ws: WebSocket, code: Int, reason: String) {
            Log.d(TAG, "WS onClosed $code $reason")
        }
    }

    // ─── Audio Pump ───────────────────────────────────────────────────────────────

    private fun startAudioPump() {
        val ar = audioRecord ?: run {
            Log.e(TAG, "startAudioPump: audioRecord is null!")
            return
        }
        ar.startRecording()
        Log.d(TAG, "startAudioPump: AudioRecord recordingState=${ar.recordingState} (1=stopped, 3=recording), state=${ar.state}")
        pumpJob = scope.launch {
            val buf = ByteArray(FRAME_BYTES)
            var sentCount = 0L
            var sentBytes = 0L
            var lastReportMs = System.currentTimeMillis()
            var maxAmp = 0
            while (isActive && isAudioRunning &&
                ar.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                val read = ar.read(buf, 0, buf.size)
                if (read > 0) {
                    // sample peak amplitude (16-bit PCM little-endian)
                    var i = 0
                    while (i + 1 < read) {
                        val s = (buf[i + 1].toInt() shl 8) or (buf[i].toInt() and 0xFF)
                        val abs = if (s < 0) -s else s
                        if (abs > maxAmp) maxAmp = abs
                        i += 2
                    }
                    sendProto(buildAudioFrame(buf.copyOf(read)))
                    sentCount++
                    sentBytes += read
                    val now = System.currentTimeMillis()
                    if (now - lastReportMs >= 1000L) {
                        Log.d(TAG, "audioPump stats (last ${now - lastReportMs}ms): frames=$sentCount bytes=$sentBytes peakAmp=$maxAmp wsAlive=${webSocket != null}")
                        sentCount = 0
                        sentBytes = 0
                        maxAmp = 0
                        lastReportMs = now
                    }
                } else if (read < 0) {
                    Log.e(TAG, "audioPump: AudioRecord.read returned error $read")
                }
            }
            Log.d(TAG, "Audio pump stopped (isActive=$isActive isAudioRunning=$isAudioRunning recState=${ar.recordingState})")
        }
    }

    // ─── 音量增益 ──────────────────────────────────────────────────────────────

    /**
     * 对 16-bit PCM 数据施加软件增益，防止 VOICE_COMMUNICATION 音量偏小。
     */
    private fun amplifyPcm(data: ByteArray): ByteArray {
        if (VOLUME_GAIN == 1.0f) return data
        val buf = java.nio.ByteBuffer.wrap(data.copyOf()).order(java.nio.ByteOrder.LITTLE_ENDIAN)
        val out = java.nio.ByteBuffer.allocate(data.size).order(java.nio.ByteOrder.LITTLE_ENDIAN)
        while (buf.remaining() >= 2) {
            val sample = (buf.short.toFloat() * VOLUME_GAIN)
                .toInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
            out.putShort(sample.toShort())
        }
        return out.array()
    }

    @Volatile private var ttsRxCount = 0L
    @Volatile private var ttsRxBytes = 0L
    @Volatile private var ttsRxReportMs = 0L
    /** 当前一句的段尾 final 信号是否已发出，避免 TTS_ENDED + TRANS_END 重复触发。 */
    @Volatile private var ttsFinalSentForRound = false

    /** 推一个 isFinal=true 的空帧给下游 sink，标记本句 TTS 音频结束（段边界）。 */
    private fun emitTtsFinalOnce(reason: String) {
        if (ttsFinalSentForRound) return
        if (!externalMode) return  // self-mic 模式没有下游 sink，不需要段尾信号
        val sink = externalSink ?: return
        ttsFinalSentForRound = true
        Log.d(TAG, "emitTtsFinal: reason=$reason (sink flush)")
        sink.onTtsFrame(
            ExternalAudioFrame(
                codec = ExternalAudioFormat.Codec.PCM_S16LE,
                sampleRate = MIC_SAMPLE_RATE,
                channels = 1,
                bytes = ByteArray(0),
                isFinal = true,
            )
        )
    }

    /**
     * 24 kHz mono PCM_S16LE → 16 kHz mono PCM_S16LE 线性插值降采样（3:2）。
     * 简单的 lerp，无 LPF——会引入轻微高频混叠，但语音 (<4 kHz) 可接受；
     * 通话翻译要求耳机端 16 kHz 输入，必须做这一步。
     */
    private fun downsample24kTo16k(input: ByteArray): ByteArray {
        if (input.size < 2) return input
        val inSamples = input.size / 2
        val outSamples = (inSamples * 2) / 3
        if (outSamples <= 0) return ByteArray(0)
        val out = ByteArray(outSamples * 2)
        val inBuf = java.nio.ByteBuffer.wrap(input).order(java.nio.ByteOrder.LITTLE_ENDIAN)
        val outBuf = java.nio.ByteBuffer.wrap(out).order(java.nio.ByteOrder.LITTLE_ENDIAN)
        for (i in 0 until outSamples) {
            // src 索引 = i * 1.5
            val srcIdx2 = i * 3 // 用整数运算：srcIdx 表示 i*1.5 的 *2 倍
            val baseIdx = srcIdx2 / 2
            val frac = (srcIdx2 % 2) // 0 → frac=0, 1 → frac=0.5
            val s0 = inBuf.getShort(baseIdx * 2).toInt()
            val s1 = if (baseIdx + 1 < inSamples) inBuf.getShort((baseIdx + 1) * 2).toInt() else s0
            val interp = if (frac == 0) s0 else (s0 + s1) / 2
            outBuf.putShort(i * 2, interp.toShort())
        }
        return out
    }

    private fun writeAudio(data: ByteArray) {
        if (data.isEmpty()) return
        ttsRxCount++
        ttsRxBytes += data.size
        val now = System.currentTimeMillis()
        if (now - ttsRxReportMs >= 1000L) {
            Log.d(TAG, "ttsRx stats (last 1s): frames=$ttsRxCount bytes=$ttsRxBytes externalMode=$externalMode sinkBound=${externalSink != null}")
            ttsRxCount = 0
            ttsRxBytes = 0
            ttsRxReportMs = now
        }
        // 外部音频模式：不放本地扬声器，回写给 sink，由编排器决定下游去向（如灌回耳机）。
        // 注：外部模式下不应用软件增益——耳机端通常自带输出增益，避免重复放大产生 clipping。
        if (externalMode) {
            val sink = externalSink
            if (sink == null) {
                Log.w(TAG, "writeAudio: externalMode but sink is null — TTS frame dropped (${data.size}B)")
                return
            }
            // 火山 AST 输出 24 kHz PCM；通话翻译耳机端只接受 AudioFormat.standard
            // = 16 kHz mono PCM（杰理 feedTranslatedAudio 在非 16k 时 silently
            // 返回 false，对方就听不到声音）。runner 层负责重采样到 16k —— 符合
            // local_plugins/CLAUDE.md §11.4 "agent runner 必须输出标准格式"。
            val pcm16k = downsample24kTo16k(data)
            sink.onTtsFrame(
                ExternalAudioFrame(
                    codec = ExternalAudioFormat.Codec.PCM_S16LE,
                    sampleRate = MIC_SAMPLE_RATE, // 16000
                    channels = 1,
                    bytes = pcm16k,
                )
            )
            return
        }
        val amplified = amplifyPcm(data)
        audioTrack?.write(amplified, 0, amplified.size)
    }

    // ─── Hardware Init ────────────────────────────────────────────────────────────

    private fun setupAudioRecord() {
        val minBuf = AudioRecord.getMinBufferSize(
            MIC_SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val bufSize = maxOf(minBuf, MIC_SAMPLE_RATE * 2 * 2)
        val ar = AudioRecord(
            MediaRecorder.AudioSource.VOICE_COMMUNICATION,
            MIC_SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT, bufSize,
        )
        audioRecord = ar
        // 1=STATE_INITIALIZED 即就绪；0=STATE_UNINITIALIZED 表示构造失败（权限 / 被占用）。
        val arState = ar.state
        if (arState != AudioRecord.STATE_INITIALIZED) {
            Log.e(TAG, "AudioRecord NOT initialized (state=$arState) — RECORD_AUDIO 权限缺失或麦克风被占用")
        }
        val sid = ar.audioSessionId
        if (AcousticEchoCanceler.isAvailable()) aec = AcousticEchoCanceler.create(sid)?.also { it.enabled = true }
        if (NoiseSuppressor.isAvailable())      ns  = NoiseSuppressor.create(sid)?.also { it.enabled = true }
        Log.d(TAG, "AudioRecord created bufSize=$bufSize state=$arState AEC=${aec != null} NS=${ns != null}")
    }

    private fun setupAudioTrack() {
        // 在创建 AudioTrack 前应用音频输出路由设置
        AudioOutputManager.applyMode()

        val minBuf = AudioTrack.getMinBufferSize(
            TTS_SAMPLE_RATE, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
        audioTrack = AudioTrack(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build(),
            AudioFormat.Builder()
                .setSampleRate(TTS_SAMPLE_RATE)
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                .build(),
            minBuf * 4,
            AudioTrack.MODE_STREAM,
            AudioManager.AUDIO_SESSION_ID_GENERATE,
        )
        audioTrack?.play()
        Log.d(TAG, "AudioTrack created sampleRate=$TTS_SAMPLE_RATE")
    }
}
