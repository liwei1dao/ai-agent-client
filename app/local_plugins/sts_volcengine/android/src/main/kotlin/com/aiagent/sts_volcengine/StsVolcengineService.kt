package com.aiagent.sts_volcengine

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
import com.aiagent.plugin_interface.AudioOutputManager
import com.aiagent.plugin_interface.NativeStsService
import com.aiagent.plugin_interface.StsCallback
import kotlinx.coroutines.*
import okhttp3.*
import okio.ByteString
import okio.ByteString.Companion.toByteString
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.TimeUnit
import java.util.zip.GZIPInputStream
import java.util.zip.GZIPOutputStream

/**
 * StsVolcengineService — 火山引擎实时语音大模型（端到端语音对话）
 *
 * 协议：火山引擎二进制帧协议
 *   WebSocket  wss://openspeech.bytedance.com/api/v3/realtime/dialogue
 *   4 字节 Header + Body（event [+ sessionId] + gzip(payload)）
 *
 * 流程：
 *   1. 连接 WebSocket（X-Api-* 鉴权头，X-Api-App-Key 为固定平台常量）
 *   2. 发送 StartConnection (event=1)，无 sessionId 字段
 *      → 收到 ConnectionStarted (event=50)，从二进制字段获取 sessionId
 *   3. 发送 StartSession (event=100)，携带 sessionId + gzip(payload)
 *      → 收到 SessionStarted (event=150)
 *   4. 持续发送音频帧 (event=200)，携带 sessionId + gzip(PCM)
 *   5. 结束时发送 FinishSession (event=102) + FinishConnection (event=2)
 *
 * 关键：
 *   - X-Api-App-Key 是固定的 SDK 平台常量，不是用户配置项
 *   - sessionId 从 ConnectionStarted(50) 响应的二进制字段获取
 *   - 所有 payload（JSON 和音频）均需 gzip 压缩
 *   - 服务端 TTS 输出 24kHz PCM，AudioTrack 需配置 24000 Hz
 */
class StsVolcengineService(private val appContext: Context) : NativeStsService {

    companion object {
        private const val TAG = "StsVolcengineService"
        private const val MIC_SAMPLE_RATE = 16000              // 麦克风采样率（ASR 输入）
        private const val TTS_SAMPLE_RATE = 24000              // 服务端 TTS 输出采样率
        private const val FRAME_BYTES = 3200                   // 100ms @ 16kHz 16-bit mono
        private const val VOLUME_GAIN = 3.0f                   // 软件增益倍数（服务端返回音量偏小）
        private const val WS_URL =
            "wss://openspeech.bytedance.com/api/v3/realtime/dialogue"

        // 固定平台常量（SDK 标识，非用户配置）
        private const val FIXED_RESOURCE_ID = "volc.speech.dialog"
        private const val FIXED_APP_KEY     = "PlgvMymc7f3tQnJ6"

        // ── 二进制协议常量 ──
        // Header byte 0: version=1, headerSize=1 (4 bytes)
        private const val HEADER_B0: Byte = 0x11.toByte()

        // Message types (upper nibble of byte 1)
        private const val TYPE_FULL_CLIENT: Int     = 0x10
        private const val TYPE_AUDIO_CLIENT: Int    = 0x20
        private const val TYPE_FULL_SERVER: Int     = 0x90
        private const val TYPE_AUDIO_SERVER: Int    = 0xB0
        private const val TYPE_ERROR: Int           = 0xF0

        // Flags (lower nibble of byte 1)
        private const val FLAG_WITH_EVENT:    Int = 0x04
        private const val FLAG_NEG_SEQUENCE:  Int = 0x02   // 最后一帧标记

        // Serialization (upper nibble of byte 2)
        private const val SER_NONE: Int = 0x00
        private const val SER_JSON: Int = 0x10

        // Compression (lower nibble of byte 2)
        private const val COMPRESS_NONE: Int = 0x00
        private const val COMPRESS_GZIP: Int = 0x01

        // Header byte 2 组合
        private const val HDR2_JSON_GZIP: Byte = (SER_JSON or COMPRESS_GZIP).toByte()  // 0x11
        private const val HDR2_RAW_GZIP:  Byte = (SER_NONE or COMPRESS_GZIP).toByte()  // 0x01

        // Event codes（客户端发送）
        private const val EVT_START_CONNECTION: Int  = 1
        private const val EVT_FINISH_CONNECTION: Int = 2
        private const val EVT_START_SESSION: Int     = 100
        private const val EVT_FINISH_SESSION: Int    = 102
        private const val EVT_SEND_AUDIO: Int        = 200

        // Event codes（服务端响应）
        private const val EVT_CONNECTION_STARTED:  Int = 50
        private const val EVT_CONNECTION_FAILED:   Int = 51
        private const val EVT_CONNECTION_FINISHED: Int = 52
        private const val EVT_SESSION_STARTED:     Int = 150
        private const val EVT_SESSION_FIN_OK:      Int = 152
        private const val EVT_SESSION_FIN_ERR:     Int = 153
        private const val EVT_TTS_TYPE:            Int = 350   // TTS 类型标记
        private const val EVT_TTS_ENDED:           Int = 359   // TTS 播放完毕
        private const val EVT_CLEAR_AUDIO:         Int = 450   // 用户开始说话 → 清空播放缓冲
        private const val EVT_ASR_RESPONSE:        Int = 451   // ASR 识别结果（用户语音文本）
        private const val EVT_USER_QUERY_ENDED:    Int = 459   // 用户说话结束，AI 开始响应
        private const val EVT_CHAT_RESPONSE:       Int = 550   // AI 回复流式文本
        private const val EVT_CHAT_ENDED:          Int = 559   // AI 回复完成

        // 连接级事件（client 发送时不含 sessionId 字段）
        private val NO_SESSION_EVENTS = setOf(EVT_START_CONNECTION, EVT_FINISH_CONNECTION)
    }

    // ── 配置字段（由 initialize() 解析） ──
    private var appId: String = ""
    private var accessToken: String = ""
    private var speaker: String = "zh_female_vv_jupiter_bigtts"
    private var systemPrompt: String = "你是一个友好、专业的 AI 语音助手，请用简洁的语言回答用户的问题。"

    // ── 回调 ──
    private var callback: StsCallback? = null

    // ── OkHttp ──
    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .writeTimeout(0, TimeUnit.MILLISECONDS)
        .build()

    // ── 状态 ──
    @Volatile private var webSocket: WebSocket? = null
    @Volatile private var audioRecord: AudioRecord? = null
    @Volatile private var audioTrack: AudioTrack? = null
    @Volatile private var aec: AcousticEchoCanceler? = null
    @Volatile private var ns: NoiseSuppressor? = null
    @Volatile private var isRunning = false       // WebSocket 连接存活
    @Volatile private var isConnected = false     // 握手完成（SessionStarted 收到）
    @Volatile private var isAudioRunning = false  // 麦克风采集 + 音频推流中
    @Volatile private var remoteSessionId: String = ""  // 从 ConnectionStarted 获取

    private var scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var pumpJob: Job? = null
    private var wsReady          = CompletableDeferred<Unit>()
    private var connectionStarted = CompletableDeferred<Unit>()
    private var sessionStarted    = CompletableDeferred<Unit>()

    // ─── NativeStsService API ─────────────────────────────────────────────────────

    override fun initialize(configJson: String, context: Context) {
        val json = JSONObject(configJson)
        appId        = json.optString("appId", "")
        accessToken  = json.optString("accessToken", "")
        speaker      = json.optString("voiceType").ifBlank { "zh_female_vv_jupiter_bigtts" }
        systemPrompt = json.optString("systemPrompt")
            .ifBlank { "你是一个友好、专业的 AI 语音助手，请用简洁的语言回答用户的问题。" }
        Log.d(TAG, "initialize: appId=$appId speaker=$speaker")
    }

    /**
     * 建立 WebSocket 连接并完成握手（StartConnection + StartSession）。
     * 不启动麦克风采集，仅准备好音频硬件（AudioRecord/AudioTrack 对象）。
     * 连接成功后回调 onConnected()，WebSocket 保持打开由 OkHttp 后台线程驱动。
     */
    override fun connect(callback: StsCallback) {
        this.callback = callback

        if (appId.isBlank() || accessToken.isBlank()) {
            Log.e(TAG, "STS config missing: appId=${appId.isBlank()} token=${accessToken.isBlank()}")
            callback.onError("config_error", "appId or accessToken missing")
            return
        }

        // Reset scope if previously cancelled
        if (!scope.isActive) {
            scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        }

        scope.launch {
            try {
                Log.d(TAG, "connect(): appId=$appId  speaker=$speaker")
                isRunning = true
                remoteSessionId = ""

                setupAudioRecord()
                setupAudioTrack()

                wsReady           = CompletableDeferred()
                connectionStarted = CompletableDeferred()
                sessionStarted    = CompletableDeferred()

                val request = Request.Builder()
                    .url(WS_URL)
                    .header("X-Api-Resource-Id", FIXED_RESOURCE_ID)
                    .header("X-Api-Access-Key",  accessToken)
                    .header("X-Api-App-Key",     FIXED_APP_KEY)
                    .header("X-Api-App-ID",      appId)
                    .header("X-Api-Connect-Id",  java.util.UUID.randomUUID().toString())
                    .build()

                webSocket = client.newWebSocket(request, createListener())

                withTimeout(15_000) { wsReady.await() }
                Log.d(TAG, "WS connected, sending StartConnection")

                // Step 1: StartConnection（无 sessionId）
                sendJsonFrame(EVT_START_CONNECTION, "{}")
                withTimeout(10_000) { connectionStarted.await() }
                Log.d(TAG, "ConnectionStarted, remoteSessionId=$remoteSessionId, sending StartSession")

                // Step 2: StartSession（含 sessionId）
                sendJsonFrame(EVT_START_SESSION, buildSessionPayload())
                withTimeout(10_000) { sessionStarted.await() }
                Log.d(TAG, "SessionStarted — ready, waiting for startAudio()")

                isConnected = true
                callback.onConnected()
                callback.onStateChanged("idle")

            } catch (e: CancellationException) {
                isRunning = false
                isConnected = false
                throw e
            } catch (e: Exception) {
                Log.e(TAG, "STS connect failed: ${e.message}", e)
                isRunning = false
                isConnected = false
                callback.onError("sts_error", e.message ?: "unknown")
            }
        }
    }

    /**
     * 开始发送音频（"接听"）：启动麦克风采集 + 音频推流。
     * 必须在 connect() 成功之后调用。
     */
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
        callback?.onStateChanged("listening")
    }

    /**
     * 停止发送音频（"挂断"）：停止麦克风采集 + 音频推流。
     * WebSocket 保持连接，仍可接收 TTS 音频和 AI 文字。
     */
    override fun stopAudio() {
        Log.d(TAG, "stopAudio()")
        isAudioRunning = false
        pumpJob?.cancel()
        pumpJob = null
        runCatching { audioRecord?.stop() }
        // 清空 AudioTrack 缓冲区，立即停止 TTS 播放
        runCatching { audioTrack?.pause(); audioTrack?.flush(); audioTrack?.play() }
        callback?.onStateChanged("idle")
    }

    /**
     * 打断 TTS 播放（用户开口说话时由 EVT_CLEAR_AUDIO 触发）。
     * 仅清空 AudioTrack 缓冲区，不影响 WebSocket 或麦克风。
     */
    override fun interrupt() {
        Log.d(TAG, "interrupt() — flush TTS buffer")
        runCatching { audioTrack?.flush() }
    }

    /**
     * 完全释放（退出聊天界面）：停止音频 + 关闭 WebSocket + 释放硬件资源。
     */
    override fun release() {
        Log.d(TAG, "release()")
        stopAudio()
        isRunning = false
        isConnected = false
        val sid = remoteSessionId
        remoteSessionId = ""
        try {
            if (sid.isNotBlank()) sendJsonFrame(EVT_FINISH_SESSION, "{}")
            sendJsonFrame(EVT_FINISH_CONNECTION, "{}")
        } catch (_: Exception) {}
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

    // ─── 二进制帧构建 ────────────────────────────────────────────────────────────

    /**
     * 发送 FullClient JSON 帧（gzip 压缩 payload）
     * 连接级事件（1/2）不含 sessionId 段；会话级事件（100/102）含 sessionId。
     */
    private fun sendJsonFrame(event: Int, jsonPayload: String) {
        val body        = gzip(jsonPayload.toByteArray(Charsets.UTF_8))
        val skipSession = event in NO_SESSION_EVENTS
        val sidBytes    = remoteSessionId.toByteArray(Charsets.UTF_8)

        var sz = 4 + 4 + body.size   // event + payloadLen + payload
        if (!skipSession) sz += 4 + sidBytes.size

        val buf = ByteBuffer.allocate(4 + sz).order(ByteOrder.BIG_ENDIAN)
        buf.put(HEADER_B0)
        buf.put((TYPE_FULL_CLIENT or FLAG_WITH_EVENT).toByte())
        buf.put(HDR2_JSON_GZIP)
        buf.put(0x00)

        buf.putInt(event)
        if (!skipSession) {
            buf.putInt(sidBytes.size)
            buf.put(sidBytes)
        }
        buf.putInt(body.size)
        buf.put(body)

        Log.d(TAG, "TX event=$event  size=${buf.capacity()}  payload=${jsonPayload.take(120)}")
        webSocket?.send(buf.array().toByteString())
    }

    /**
     * 发送音频帧（AudioOnlyClient + event=200，gzip 压缩 PCM）
     */
    private fun sendAudioFrame(pcmData: ByteArray, size: Int) {
        val body     = gzip(pcmData.copyOf(size))
        val sidBytes = remoteSessionId.toByteArray(Charsets.UTF_8)
        val sz       = 4 + 4 + sidBytes.size + 4 + body.size

        val buf = ByteBuffer.allocate(4 + sz).order(ByteOrder.BIG_ENDIAN)
        buf.put(HEADER_B0)
        buf.put((TYPE_AUDIO_CLIENT or FLAG_WITH_EVENT).toByte())
        buf.put(HDR2_RAW_GZIP)
        buf.put(0x00)

        buf.putInt(EVT_SEND_AUDIO)
        buf.putInt(sidBytes.size)
        buf.put(sidBytes)
        buf.putInt(body.size)
        buf.put(body)

        webSocket?.send(buf.array().toByteString())
    }

    // ─── 服务端帧解析 ────────────────────────────────────────────────────────────

    /**
     * 解析服务端二进制帧
     *
     * 对于 SERVER_FULL_RESPONSE 和 SERVER_ACK，帧体格式：
     *   [可选 negSeq(4)] [可选 event(4)] [sid_len(4)] [sid] [payload_len(4)] [payload]
     * payload 可能是 gzip 压缩的，根据 byte2 低4位判断。
     */
    private fun parseServerFrame(data: ByteArray) {
        if (data.size < 4) { Log.w(TAG, "RX frame too short: ${data.size}"); return }

        val b1 = data[1].toInt() and 0xFF
        val b2 = data[2].toInt() and 0xFF

        val msgType  = b1 and 0xF0
        val flags    = b1 and 0x0F
        val compress = b2 and 0x0F
        val serType  = b2 and 0xF0

        val hasNegSeq = (flags and FLAG_NEG_SEQUENCE) != 0
        val hasEvent  = (flags and FLAG_WITH_EVENT)   != 0

        var pos = 4  // 跳过 4 字节 header

        // 负序列号（最后一帧标记）
        if (hasNegSeq && pos + 4 <= data.size) pos += 4

        // event
        var event = -1
        if (hasEvent && pos + 4 <= data.size) {
            event = ByteBuffer.wrap(data, pos, 4).order(ByteOrder.BIG_ENDIAN).int
            pos += 4
        }

        when (msgType) {

            TYPE_FULL_SERVER, TYPE_AUDIO_SERVER -> {
                // session_id（服务端响应始终包含此字段）
                if (pos + 4 > data.size) return
                val sidLen = ByteBuffer.wrap(data, pos, 4).order(ByteOrder.BIG_ENDIAN).int
                pos += 4
                if (sidLen > 0) {
                    if (pos + sidLen > data.size) return
                    val sid = String(data, pos, sidLen, Charsets.UTF_8)
                    if (remoteSessionId.isBlank() && sid.isNotBlank()) {
                        remoteSessionId = sid
                        Log.d(TAG, "Got remoteSessionId: $remoteSessionId")
                    }
                    pos += sidLen
                }

                // payload
                if (pos + 4 > data.size) return
                val payloadLen = ByteBuffer.wrap(data, pos, 4).order(ByteOrder.BIG_ENDIAN).int
                pos += 4
                if (payloadLen <= 0 || pos + payloadLen > data.size) {
                    Log.d(TAG, "RX type=0x${msgType.toString(16)} event=$event payloadSize=0")
                    if (msgType == TYPE_FULL_SERVER) handleServerEvent(event, ByteArray(0), serType, compress)
                    return
                }
                var payload = data.copyOfRange(pos, pos + payloadLen)
                if (compress == COMPRESS_GZIP) {
                    payload = runCatching { ungzip(payload) }.getOrElse {
                        Log.w(TAG, "gzip decompress failed: ${it.message}")
                        payload
                    }
                }

                Log.d(TAG, "RX type=0x${msgType.toString(16)} event=$event payloadSize=${payload.size}")

                if (msgType == TYPE_FULL_SERVER) {
                    handleServerEvent(event, payload, serType, compress)
                } else {
                    // TYPE_AUDIO_SERVER: PCM 增益后写入 AudioTrack + 回调
                    if (payload.isNotEmpty()) {
                        val amplified = amplifyPcm(payload)
                        audioTrack?.write(amplified, 0, amplified.size)
                        callback?.onTtsAudioChunk(amplified)
                    }
                }
            }

            TYPE_ERROR -> {
                // Error 帧: header(4) + error_code(4) + payload_len(4) + payload
                val errText = if (data.size >= 12) {
                    val errCode = ByteBuffer.wrap(data, 4, 4).order(ByteOrder.BIG_ENDIAN).int
                    val pLen    = ByteBuffer.wrap(data, 8, 4).order(ByteOrder.BIG_ENDIAN).int
                    if (pLen > 0 && 12 + pLen <= data.size) {
                        var raw = data.copyOfRange(12, 12 + pLen)
                        if (compress == COMPRESS_GZIP) raw = runCatching { ungzip(raw) }.getOrElse { raw }
                        "code=$errCode  ${String(raw, Charsets.UTF_8)}"
                    } else "code=$errCode"
                } else "unknown (raw=${data.take(16).joinToString(" ") { "%02x".format(it) }})"
                Log.e(TAG, "Server error: $errText")
                callback?.onError("sts_server_error", errText)
            }
        }
    }

    private fun handleServerEvent(event: Int, payload: ByteArray, serType: Int, compress: Int) {
        val jsonStr = if (serType == SER_JSON && payload.isNotEmpty()) String(payload, Charsets.UTF_8) else null
        val json    = runCatching { if (jsonStr != null) JSONObject(jsonStr) else null }.getOrNull()

        Log.d(TAG, "Server event=$event  json=${jsonStr?.take(200)}")

        when (event) {
            EVT_CONNECTION_STARTED  -> { Log.d(TAG, "ConnectionStarted!"); connectionStarted.complete(Unit) }
            EVT_CONNECTION_FAILED   -> {
                val msg = json?.optString("message") ?: "connection failed"
                Log.e(TAG, "ConnectionFailed: $msg")
                connectionStarted.completeExceptionally(Exception(msg))
            }
            EVT_CONNECTION_FINISHED -> {
                Log.d(TAG, "ConnectionFinished")
                callback?.onDisconnected()
            }
            EVT_SESSION_STARTED     -> { Log.d(TAG, "SessionStarted!"); sessionStarted.complete(Unit) }
            EVT_SESSION_FIN_OK, EVT_SESSION_FIN_ERR -> Log.d(TAG, "SessionFinished event=$event")

            EVT_CLEAR_AUDIO -> {
                // 用户开始说话，清空 AudioTrack 缓冲区，触发打断
                Log.d(TAG, "ClearAudio (user speaking)")
                runCatching { audioTrack?.flush() }
                callback?.onSpeechStart()
                callback?.onStateChanged("listening")
            }

            EVT_ASR_RESPONSE -> {
                // ASR 用户语音识别结果
                // 文本在 extra.origin_text，终态标志在 extra.endpoint
                val extra   = json?.optJSONObject("extra")
                val text    = extra?.optString("origin_text") ?: ""
                val isFinal = extra?.optBoolean("endpoint", false) ?: false
                Log.d(TAG, "ASR isFinal=$isFinal text=\"$text\"")
                if (text.isNotBlank()) {
                    if (isFinal) {
                        callback?.onSttFinalResult(text)
                    } else {
                        callback?.onSttPartialResult(text)
                    }
                }
            }

            EVT_USER_QUERY_ENDED -> {
                Log.d(TAG, "UserQueryEnded — AI responding")
                callback?.onStateChanged("llm")
            }

            EVT_CHAT_RESPONSE -> {
                // AI 回复流式文本（逐字/逐词推送）
                val content = json?.optString("content") ?: ""
                if (content.isNotBlank()) {
                    Log.v(TAG, "ChatResponse content=\"$content\"")
                    callback?.onStateChanged("playing")
                }
            }

            EVT_CHAT_ENDED -> {
                // AI 回复完成
                val replyId = json?.optString("reply_id") ?: ""
                Log.d(TAG, "ChatEnded replyId=$replyId")
                // Notify sentence done with the full reply text if available
                val content = json?.optString("content") ?: ""
                if (content.isNotBlank()) {
                    callback?.onSentenceDone(content)
                }
            }

            EVT_TTS_ENDED, EVT_TTS_TYPE -> {
                Log.d(TAG, "TTS event=$event")
                if (event == EVT_TTS_ENDED) callback?.onStateChanged("listening")
            }

            else -> {
                if (json != null) handleSessionEvent(json)
                else if (event != -1) Log.d(TAG, "Unhandled server event=$event")
            }
        }
    }

    private fun handleSessionEvent(json: JSONObject) {
        // 服务端 JSON 事件字段可能在顶层 "event" 或内嵌
        val eventName = json.optString("event").ifBlank { json.optString("type") }

        when (eventName) {
            "SentenceRecognized" -> {
                val text = json.optString("text").ifBlank {
                    json.optJSONObject("payload")?.optString("text") ?: ""
                }
                Log.d(TAG, "SentenceRecognized: \"$text\"")
                if (text.isNotBlank()) {
                    callback?.onSttFinalResult(text)
                    callback?.onStateChanged("llm")
                }
            }
            "TTSSentenceStart" -> {
                Log.d(TAG, "TTSSentenceStart")
                callback?.onStateChanged("playing")
            }
            "TTSDone" -> {
                Log.d(TAG, "TTSDone")
                callback?.onStateChanged("listening")
            }
            "BotReady" -> Log.d(TAG, "BotReady")
            "BotError" -> {
                val code = json.optString("error_code", "bot_error")
                val msg  = json.optString("error_msg", json.optString("message", "BotError"))
                Log.e(TAG, "BotError: $code — $msg")
                callback?.onError(code, msg)
            }
            else -> if (eventName.isNotBlank()) Log.d(TAG, "Unhandled session event=$eventName  json=${json.toString().take(200)}")
        }
    }

    // ─── WebSocket Listener ──────────────────────────────────────────────────────

    private fun createListener() = object : WebSocketListener() {

        override fun onOpen(ws: WebSocket, response: Response) {
            Log.d(TAG, "WS onOpen")
            wsReady.complete(Unit)
        }

        override fun onMessage(ws: WebSocket, text: String) {
            Log.w(TAG, "WS ← unexpected text: ${text.take(200)}")
        }

        override fun onMessage(ws: WebSocket, bytes: ByteString) {
            val data = bytes.toByteArray()
            Log.v(TAG, "WS ← binary ${data.size}B  hdr=${data.take(4).map { "0x%02x".format(it) }}")
            try { parseServerFrame(data) } catch (e: Exception) {
                Log.e(TAG, "parseServerFrame error: ${e.message}", e)
            }
        }

        override fun onFailure(ws: WebSocket, t: Throwable, response: Response?) {
            Log.e(TAG, "WS failure code=${response?.code}  ${t.message}")
            runCatching { wsReady.completeExceptionally(t) }
            runCatching { connectionStarted.completeExceptionally(t) }
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
            callback?.onDisconnected()
        }
    }

    // ─── StartSession payload ────────────────────────────────────────────────────

    private fun buildSessionPayload(): String {
        return JSONObject().apply {
            put("asr", JSONObject().apply {
                put("extra", JSONObject().apply {
                    put("end_smooth_window_ms", 1500)
                })
            })
            put("tts", JSONObject().apply {
                put("speaker", speaker)
                put("audio_config", JSONObject().apply {
                    put("channel", 1)
                    put("format", "pcm_s16le")
                    put("sample_rate", TTS_SAMPLE_RATE)
                })
            })
            put("dialog", JSONObject().apply {
                put("system_role", systemPrompt)
                put("extra", JSONObject().apply {
                    put("strict_audit", false)
                    put("recv_timeout", 10)
                    put("input_mod", "audio")
                    put("model", "O")
                })
            })
        }.toString()
    }

    // ─── 音频推流 ─────────────────────────────────────────────────────────────────

    private fun startAudioPump() {
        val ar = audioRecord ?: return
        ar.startRecording()
        pumpJob = scope.launch {
            val buf = ByteArray(FRAME_BYTES)
            while (isActive && isAudioRunning &&
                ar.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                val read = ar.read(buf, 0, buf.size)
                if (read > 0) sendAudioFrame(buf, read)
            }
            Log.d(TAG, "Audio pump stopped")
        }
    }

    // ─── 硬件初始化 ──────────────────────────────────────────────────────────────

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

        // TTS 输出 24kHz，AudioTrack 必须匹配
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

    // ─── 音量增益 ──────────────────────────────────────────────────────────────

    /**
     * 对 16-bit PCM 数据施加软件增益，防止 VOICE_COMMUNICATION 音量偏小。
     * 采用 clamp 避免溢出失真。
     */
    private fun amplifyPcm(data: ByteArray): ByteArray {
        if (VOLUME_GAIN == 1.0f) return data
        val buf = ByteBuffer.wrap(data.copyOf()).order(ByteOrder.LITTLE_ENDIAN)
        val out = ByteBuffer.allocate(data.size).order(ByteOrder.LITTLE_ENDIAN)
        while (buf.remaining() >= 2) {
            val sample = (buf.short.toFloat() * VOLUME_GAIN)
                .toInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
            out.putShort(sample.toShort())
        }
        return out.array()
    }

    // ─── Gzip 工具 ───────────────────────────────────────────────────────────────

    private fun gzip(data: ByteArray): ByteArray {
        val out = ByteArrayOutputStream()
        GZIPOutputStream(out).use { it.write(data) }
        return out.toByteArray()
    }

    private fun ungzip(data: ByteArray): ByteArray =
        GZIPInputStream(ByteArrayInputStream(data)).readBytes()
}
