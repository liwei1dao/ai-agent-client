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

        // Event codes (Type enum from events.proto)
        private const val EVT_START_SESSION    = 100
        private const val EVT_FINISH_SESSION   = 102
        private const val EVT_SESSION_STARTED  = 150
        private const val EVT_SESSION_FINISHED = 152
        private const val EVT_SESSION_FAILED   = 153
        private const val EVT_USAGE_RESPONSE   = 154
        private const val EVT_TASK_REQUEST     = 200
        private const val EVT_TTS_SENTENCE_START = 350
        private const val EVT_TTS_ENDED        = 359
        private const val EVT_ASR_RESPONSE     = 451
        private const val EVT_SRC_SUBTITLE_START = 650
        private const val EVT_SRC_SUBTITLE     = 651
        private const val EVT_SRC_SUBTITLE_END = 652
        private const val EVT_TRANS_SUBTITLE_START = 653
        private const val EVT_TRANS_SUBTITLE   = 654
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
    @Volatile private var remoteSessionId: String = ""
    @Volatile private var connectId: String = ""
    @Volatile private var srcLang: String = "zh"
    @Volatile private var dstLang: String = "en"
    @Volatile private var isBidirectional = false

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
        srcLang = config.optString("srcLang").ifBlank { "zh" }
        dstLang = config.optString("dstLang").ifBlank { "en" }
        Log.d(TAG, "initialize: appKey=${appKey.take(8)}... srcLang=$srcLang dstLang=$dstLang")
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
                isBidirectional = setOf(srcLang, dstLang) == setOf("zh", "en")

                Log.d(TAG, "connect(): appKey=$appKey resourceId=$resourceId srcLang=$srcLang dstLang=$dstLang")

                setupAudioRecord()
                setupAudioTrack()

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
        Log.d(TAG, "startAudio()")
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
        // 中英互译时协议层使用 "zhen"（火山引擎双向模式要求）
        val wsSource = if (isBidirectional) "zhen" else srcLang
        val wsTarget = if (isBidirectional) "zhen" else dstLang
        return encMsg(1, encStr(5, connectId) + encStr(6, remoteSessionId)) +
               encEnum(2, event) +
               encMsg(3, encStr(1, "ast_android") + encStr(2, "ast_android")) +
               encMsg(4, srcAudioFields) +
               encMsg(5, encStr(4, "wav") + encInt(7, TTS_SAMPLE_RATE) + encInt(8, 16) + encInt(9, 1)) +
               encMsg(6, encStr(1, "s2s") + encStr(2, wsSource) + encStr(3, wsTarget))
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

    // ─── 双向语言检测 ──────────────────────────────────────────────────────────

    /**
     * 通过 CJK 字符占比判断文本语言（中英双向模式专用）。
     * 汉字占比 > 30% -> zh，否则 -> en。
     */
    private fun detectTextLang(text: String): String {
        val cjk = text.count { it in '\u4e00'..'\u9fff' }
        val total = text.count { !it.isWhitespace() }
        return if (total == 0 || cjk.toFloat() / total > 0.3f) "zh" else "en"
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
                runCatching { sessionStarted.completeExceptionally(Exception(err)) }
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
                srcSubtitleAccum.clear()
                val cb = callback
                if (cb != null) {
                    beginRound(cb)
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
                    maybeEndRound(cb)
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
            }

            EVT_TTS_SENTENCE_START -> {
                Log.d(TAG, "TTSSentenceStart")
                if (audioData.isNotEmpty()) writeAudio(audioData)
            }

            EVT_TTS_ENDED -> {
                Log.d(TAG, "TTSEnded")
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
            Log.e(TAG, "WS failure code=${response?.code}  ${t.message}")
            runCatching { wsReady.completeExceptionally(t) }
            runCatching { sessionStarted.completeExceptionally(t) }
            if (isRunning) callback?.onError("ws_error",
                "WebSocket error ${response?.code}: ${t.message}")
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
        val ar = audioRecord ?: return
        ar.startRecording()
        pumpJob = scope.launch {
            val buf = ByteArray(FRAME_BYTES)
            while (isActive && isAudioRunning &&
                ar.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                val read = ar.read(buf, 0, buf.size)
                if (read > 0) sendProto(buildAudioFrame(buf.copyOf(read)))
            }
            Log.d(TAG, "Audio pump stopped")
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

    private fun writeAudio(data: ByteArray) {
        if (data.isNotEmpty()) {
            val amplified = amplifyPcm(data)
            audioTrack?.write(amplified, 0, amplified.size)
        }
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
        val sid = ar.audioSessionId
        if (AcousticEchoCanceler.isAvailable()) aec = AcousticEchoCanceler.create(sid)?.also { it.enabled = true }
        if (NoiseSuppressor.isAvailable())      ns  = NoiseSuppressor.create(sid)?.also { it.enabled = true }
        Log.d(TAG, "AudioRecord created bufSize=$bufSize AEC=${aec != null}")
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
