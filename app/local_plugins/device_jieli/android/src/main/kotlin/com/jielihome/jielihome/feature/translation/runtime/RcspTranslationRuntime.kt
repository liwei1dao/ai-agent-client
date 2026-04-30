package com.jielihome.jielihome.feature.translation.runtime

import android.bluetooth.BluetoothDevice
import com.jieli.bluetooth.bean.translation.AudioData
import com.jieli.bluetooth.bean.translation.TranslationMode
import com.jieli.bluetooth.constant.Constants
import com.jieli.bluetooth.impl.JL_BluetoothManager
import com.jieli.bluetooth.impl.rcsp.translation.TranslationImpl
import com.jieli.bluetooth.interfaces.rcsp.callback.OnRcspActionCallback
import com.jieli.bluetooth.interfaces.rcsp.translation.TranslationCallback
import android.util.Log
import com.jielihome.jielihome.audio.OpusStreamDecoder
import com.jielihome.jielihome.feature.translation.TranslationStreams
import com.jieli.jl_audio_decode.callback.OnStateCallback
import com.jieli.jl_audio_decode.opus.OpusManager
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.ArrayDeque
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * RCSP 翻译模式运行时。
 *
 * audioType：
 *   - [Constants.AUDIO_TYPE_OPUS]（默认）：上行 OPUS → 解码 PCM；下行 PCM → **整段** 编码 OPUS 写回
 *   - [Constants.AUDIO_TYPE_PCM]：上下行直接走 PCM，不经编解码
 *
 * # TTS 回灌策略（与官方 demo `MachineTranslation.tryToTTS` / `OpusHelper.encodeFile` 对齐）
 *
 * 之前是流式 [com.jielihome.jielihome.audio.OpusStreamEncoder]：每出一帧 OPUS 立即包成
 * AudioData 调 [TranslationImpl.writeAudioData]，导致耳机端 RCSP 把每帧当成"独立的一段
 * TTS 起点"，解码器频繁 reset → 杂音 / 断续。
 *
 * 现在按 demo：[feedTtsPcm] 把 PCM 累积到 per-leg 缓冲；上层在每段 utterance 末尾把
 * `isFinal=true` 透传过来；runtime 这一刻：
 *   1. 把累积 PCM 写到临时 .pcm 文件；
 *   2. `OpusManager.encodeFile(pcmFile, opusFile, callback)` 离线整段编码（带 head 的默认 OpusOption）；
 *   3. 整段读出 → **一个** [AudioData] → [WriteScheduler] 单次入队下发。
 *
 * # 文件命名
 * 临时文件位于 [tempDir]，按 `tts_<source>_<seq>.<pcm|opus>` 命名；编码完成异步删除。
 *
 * # source 字段写回方向
 *   - 通话翻译给「对端听」  → AudioData.source = SOURCE_E_SCO_UP_LINK
 *   - 通话翻译给「本机听」  → AudioData.source = SOURCE_E_SCO_DOWN_LINK
 *   - 录音/音视频/面对面    → AudioData.source = SOURCE_PHONE_MIC（SDK 按 mode 自分发）
 */
class RcspTranslationRuntime(
    private val btManager: JL_BluetoothManager,
    private val device: BluetoothDevice,
    private val mode: TranslationMode,
    private val tempDir: File,
    /** 解码（或直传 PCM）后的音频上行；source 为 SDK 原值 */
    private val onPcm: (source: Int, pcm: ByteArray) -> Unit,
    private val onError: (code: Int, msg: String?) -> Unit,
    private val opusPacketSize: Int = if (mode.channel == 2) 80 else 200,
) {

    private val translationImpl = TranslationImpl(btManager, NoOpAITranslationApi(), device)
    private val isPcmMode = mode.audioType == Constants.AUDIO_TYPE_PCM
    private val sampleRateHz = mode.sampleRate.takeIf { it > 0 } ?: 16000

    /** 入栈解码器：仅 OPUS 模式下创建 */
    private val upDecoder: OpusStreamDecoder? = if (isPcmMode) null else OpusStreamDecoder(
        channel = 1,
        packetSize = opusPacketSize,
        sampleRate = sampleRateHz,
        onPcm = { pcm -> onPcm(AudioData.SOURCE_E_SCO_UP_LINK, pcm) },
        onError = { c, m -> onError(c, "upDecoder: $m") },
    )

    private val downDecoder: OpusStreamDecoder? =
        if (!isPcmMode && mode.mode == TranslationMode.MODE_CALL_TRANSLATION) OpusStreamDecoder(
            channel = 1,
            packetSize = opusPacketSize,
            sampleRate = sampleRateHz,
            onPcm = { pcm -> onPcm(AudioData.SOURCE_E_SCO_DOWN_LINK, pcm) },
            onError = { c, m -> onError(c, "downDecoder: $m") },
        ) else null

    private val stereoDecoder: OpusStreamDecoder? =
        if (!isPcmMode && mode.mode == TranslationMode.MODE_CALL_TRANSLATION_WITH_STEREO) OpusStreamDecoder(
            channel = 2, packetSize = 80,
            sampleRate = sampleRateHz,
            onPcm = { pcm -> onPcm(AudioData.SOURCE_E_SCO_MIX, pcm) },
            onError = { c, m -> onError(c, "stereoDecoder: $m") },
        ) else null

    /** 调试统计：SDK onReceiveAudioData 被回调多少次、按 (source,type) 分桶 */
    @Volatile private var rxCount = 0L
    @Volatile private var rxTypeMismatch = 0L
    @Volatile private var rxNullPayload = 0L
    @Volatile private var rxLastReportMs = 0L

    private val translationCallback = object : TranslationCallback {
        override fun onModeChange(d: BluetoothDevice, m: TranslationMode) {
            Log.d(TAG, "TranslationCallback.onModeChange: mode=${m.mode} type=${m.audioType} sr=${m.sampleRate} ch=${m.channel}")
        }

        override fun onReceiveAudioData(d: BluetoothDevice, data: AudioData) {
            rxCount++
            val now = System.currentTimeMillis()
            if (now - rxLastReportMs >= 1000L) {
                Log.d(TAG, "RX stats (last 1s): total=$rxCount typeMismatch=$rxTypeMismatch nullPayload=$rxNullPayload  expect.type=${mode.audioType}  last.source=${data.source} last.type=${data.type} payloadSize=${data.audioData?.size ?: 0}")
                rxCount = 0; rxTypeMismatch = 0; rxNullPayload = 0; rxLastReportMs = now
            }
            if (data.type != mode.audioType) {
                rxTypeMismatch++
                return
            }
            val payload = data.audioData
            if (payload == null) {
                rxNullPayload++
                return
            }
            if (isPcmMode) {
                onPcm(data.source, payload)
                return
            }
            when (data.source) {
                AudioData.SOURCE_E_SCO_UP_LINK -> upDecoder?.feedEncoded(payload)
                AudioData.SOURCE_E_SCO_DOWN_LINK -> downDecoder?.feedEncoded(payload)
                AudioData.SOURCE_E_SCO_MIX -> stereoDecoder?.feedEncoded(payload)
            }
        }

        override fun onError(d: BluetoothDevice, code: Int, msg: String) {
            Log.e(TAG, "TranslationCallback.onError code=$code msg=$msg")
            this@RcspTranslationRuntime.onError(code, msg)
        }
    }

    companion object {
        private const val TAG = "RcspTranslationRuntime"
        /** 每腿 writeAudioData 缓冲队列上限。整段下发后队列里几乎不会堆积，留 8 个槽足够。 */
        private const val WRITE_QUEUE_LIMIT = 8
        /** 单段 PCM 上限：≈ 60s 16k mono 16bit = 1.92MB，正常 utterance 远低于此值。 */
        private const val PCM_BUFFER_HARD_LIMIT_BYTES = 2 * 1024 * 1024
        /**
         * 周期性 flush 间隔：每隔此毫秒数巡检一次 buffer，**只要非空就 flush**。
         *
         * 实测：低于 1s（试过 200ms）耳机端 RCSP 解码器会被频繁 reset 直至死机，
         * 因此周期上限只能保持 1s。降低段间延迟改走"首段优先 flush"路线（B）。
         */
        private const val PERIODIC_FLUSH_MS = 1_000L
        /**
         * 首段优先 flush 阈值（路线 B）：每个 utterance 的**首段**达到此毫秒数对应字节量
         * 就立即 flush，不等周期。让用户开口到对方听到的延迟尽可能小（< 200ms）。
         *
         * 触发后转入周期模式直到 isFinal=true 重置。火山不发 isFinal 的会话里，
         * 只有第一句享受首段优先；后续句统一走 [PERIODIC_FLUSH_MS] 周期。这是为了
         * 避免连续讲话被反复识别成"新 utterance"导致每 100ms 切一段、reset 频率失控。
         */
        private const val FIRST_SEGMENT_FLUSH_MS = 100L
    }

    /**
     * 串行化的 writeAudioData 调度器（每个 source 一个）。
     *
     * RCSP/SPP 写入要求：上一帧 [writeAudioData] 的回调返回（成功或失败）之前不要再发，
     * 否则 SDK 会拒收新请求并报 "Operation in progress"。这里维护一个 in-flight ≤ 1
     * 的 FIFO 队列，溢出时丢最老的帧（保实时性，不堆积延迟）。
     */
    private class WriteScheduler(
        private val tag: String,
        private val send: (AudioData, OnRcspActionCallback<Boolean>) -> Unit,
    ) {
        private val queue = ArrayDeque<AudioData>(WRITE_QUEUE_LIMIT)
        private val inFlight = AtomicBoolean(false)
        private val lock = Any()
        @Volatile private var droppedSinceReport = 0L
        @Volatile private var lastReportMs = 0L

        fun enqueue(data: AudioData) {
            val toSend: AudioData? = synchronized(lock) {
                if (inFlight.compareAndSet(false, true)) {
                    data
                } else {
                    if (queue.size >= WRITE_QUEUE_LIMIT) {
                        queue.pollFirst() // 丢最老
                        droppedSinceReport++
                        val now = System.currentTimeMillis()
                        if (now - lastReportMs >= 1000L) {
                            Log.w(TAG, "writeAudioData[$tag] queue full, dropped=$droppedSinceReport (last 1s)")
                            droppedSinceReport = 0
                            lastReportMs = now
                        }
                    }
                    queue.offerLast(data)
                    null
                }
            }
            if (toSend != null) dispatch(toSend)
        }

        private fun dispatch(data: AudioData) {
            send(data, object : OnRcspActionCallback<Boolean> {
                override fun onSuccess(d: BluetoothDevice?, ok: Boolean?) = onComplete()
                override fun onError(d: BluetoothDevice?, err: com.jieli.bluetooth.bean.base.BaseError?) {
                    val msg = err?.message.orEmpty()
                    if (!msg.contains("Operation in progress", ignoreCase = true)) {
                        Log.w(TAG, "writeAudioData[$tag] error: code=${err?.code} msg=$msg")
                    }
                    onComplete()
                }
            })
        }

        private fun onComplete() {
            val next: AudioData? = synchronized(lock) {
                val n = queue.pollFirst()
                if (n == null) inFlight.set(false)
                n
            }
            if (next != null) dispatch(next)
        }

        fun clear() {
            synchronized(lock) {
                queue.clear()
                inFlight.set(false)
            }
        }
    }

    private val uplinkWriter = WriteScheduler("uplink") { data, cb ->
        translationImpl.writeAudioData(data, cb)
    }
    private val downlinkWriter = WriteScheduler("downlink") { data, cb ->
        translationImpl.writeAudioData(data, cb)
    }
    private val phoneMicWriter = WriteScheduler("phoneMic") { data, cb ->
        translationImpl.writeAudioData(data, cb)
    }
    /** 兜底：PCM 直传 / 未识别 source 走这条；和 OPUS 编码器互不抢 in-flight 槽位。 */
    private val rawWriter = WriteScheduler("raw") { data, cb ->
        translationImpl.writeAudioData(data, cb)
    }

    /**
     * Per-leg PCM 缓冲。`feedTtsPcm` 累积写入，`isFinal=true` 时整段编码下发后清空。
     *
     * key = outputStreamId（OUT_UPLINK / OUT_DOWNLINK / OUT_SPEAKER 等）
     */
    private val pcmBuffers = mutableMapOf<String, ByteArrayOutputStream>()
    /** 每条 leg 是否仍处于"等待首段触发"状态（路线 B 首段优先 flush 用）。 */
    private val firstSegmentPending = mutableMapOf<String, Boolean>()
    private val bufferLock = Any()
    private var encodeSeq = 0L

    /** 周期性 flush 巡检线程；start() 启动，stop() 关闭。 */
    private var flushWatcher: ScheduledExecutorService? = null

    /** 启动前置校验 + 进入翻译模式 */
    fun start(): Result<Unit> {
        if (!translationImpl.isInit) {
            return Result.failure(IllegalStateException("RCSP not init for ${device.address}"))
        }
        if (!translationImpl.isSupportTranslation) {
            return Result.failure(IllegalStateException("device does not support translation"))
        }
        if (mode.mode == TranslationMode.MODE_CALL_TRANSLATION_WITH_STEREO &&
            !translationImpl.isSupportCallTranslationWithStereo
        ) {
            return Result.failure(IllegalStateException("device does not support stereo call translation"))
        }
        if (!tempDir.exists()) tempDir.mkdirs()

        upDecoder?.start()
        downDecoder?.start()
        stereoDecoder?.start()

        translationImpl.addTranslationCallback(translationCallback)
        Log.d(TAG, "enterMode: mode=${mode.mode} type=${mode.audioType} sr=${mode.sampleRate} ch=${mode.channel} strategy=${mode.recordingStrategy} (waiting for onModeChange/onReceiveAudioData)")
        translationImpl.enterMode(mode, translationCallback)

        // OPUS 模式启动周期性 flush 巡检：每 [PERIODIC_FLUSH_MS] 切一次缓冲。
        if (!isPcmMode) startPeriodicFlushWatcher()
        return Result.success(Unit)
    }

    private fun startPeriodicFlushWatcher() {
        flushWatcher?.shutdownNow()
        val exec = Executors.newSingleThreadScheduledExecutor { r ->
            Thread(r, "rcsp-tts-flush").apply { isDaemon = true }
        }
        flushWatcher = exec
        exec.scheduleAtFixedRate(
            { runCatching { periodicFlush() } },
            PERIODIC_FLUSH_MS, PERIODIC_FLUSH_MS, TimeUnit.MILLISECONDS,
        )
    }

    /** 每秒巡检：每条 leg 的 buffer 只要非空就立即切走 + 编码 + 下发（不依赖任何外部信号）。 */
    private fun periodicFlush() {
        val toEncode = mutableListOf<Triple<Int, String, ByteArray>>()
        synchronized(bufferLock) {
            for ((leg, buf) in pcmBuffers) {
                if (buf.size() == 0) continue
                val source = when (leg) {
                    TranslationStreams.OUT_UPLINK -> AudioData.SOURCE_E_SCO_UP_LINK
                    TranslationStreams.OUT_DOWNLINK -> AudioData.SOURCE_E_SCO_DOWN_LINK
                    else -> AudioData.SOURCE_PHONE_MIC
                }
                val out = buf.toByteArray()
                buf.reset()
                Log.d(TAG, "periodicFlush: leg=$leg bytes=${out.size}")
                toEncode.add(Triple(source, leg, out))
            }
        }
        // encode 走 async，必须释放锁后做。
        for ((source, leg, pcm) in toEncode) {
            encodeAndDispatchAsync(source, leg, pcm)
        }
    }

    /**
     * 把外部翻译服务回送的 PCM 注入回耳机。
     *
     * 策略：
     *   - PCM 模式：每次调用直接当作一段 AudioData 下发（SDK 内部按 blockMtu 分片）。
     *   - OPUS 模式：纯时间驱动 flush —— 火山等端到端服务的段尾事件不可靠，
     *     不能依赖 isFinal 或字节量阈值。改为：
     *       a) feedTtsPcm 仅追加 buffer，不主动 flush（除非 isFinal=true）；
     *       b) [PERIODIC_FLUSH_MS] (1s) 巡检线程每秒切走 buffer 并整段编码下发；
     *       c) `isFinal=true` 仍短路立即 flush（兼容主动信号，不再依赖）。
     *     最大听感延迟 ≤ 1s，且短句 / 没有段尾事件的服务都不会卡死。
     *
     * @param outputStreamId 决定 source：
     *   [TranslationStreams.OUT_UPLINK] / [TranslationStreams.OUT_DOWNLINK] 用于通话翻译；
     *   其它（speaker/localPlayback）由 ModeHandler 自己处理，不会落到这里。
     * @param isFinal 本帧是否为当前 utterance 的最后一帧；触发 buffer 残余立即 flush。
     */
    fun feedTtsPcm(outputStreamId: String, pcm: ByteArray, isFinal: Boolean): Boolean {
        val source = when (outputStreamId) {
            TranslationStreams.OUT_UPLINK -> AudioData.SOURCE_E_SCO_UP_LINK
            TranslationStreams.OUT_DOWNLINK -> AudioData.SOURCE_E_SCO_DOWN_LINK
            else -> AudioData.SOURCE_PHONE_MIC
        }
        if (isPcmMode) {
            // PCM 直传：每次调用一段 AudioData。`isFinal` 在该模式下不影响下发节奏。
            writeBack(AudioData(source, Constants.AUDIO_TYPE_PCM, pcm))
            return true
        }
        // OPUS 模式：累积到 buffer，三条 flush 触发链（按优先级）：
        //   1. isFinal=true            → 立即 flush，并把首段优先重置回 true（下一句新算）
        //   2. 首段优先（路线 B）       → 当前 leg 处于 firstSegmentPending=true 且 buffer
        //                                 累积到 FIRST_SEGMENT_FLUSH_MS 字节量时立即 flush，
        //                                 让"开口到对方听见"的延迟最小化（< 200ms）
        //   3. 周期 flush（路线 A）     → 由 [PERIODIC_FLUSH_MS] 巡检线程接管
        val pendingFlush: ByteArray? = synchronized(bufferLock) {
            val buf = pcmBuffers.getOrPut(outputStreamId) { ByteArrayOutputStream() }
            if (pcm.isNotEmpty()) {
                if (buf.size() + pcm.size > PCM_BUFFER_HARD_LIMIT_BYTES) {
                    Log.w(TAG, "feedTtsPcm: leg=$outputStreamId pcm buffer hit hard limit ${PCM_BUFFER_HARD_LIMIT_BYTES}, dropping segment")
                    buf.reset()
                    return false
                }
                buf.write(pcm)
            }
            // 1) 段尾信号：立即下发尾段并把首段标志重置回 true。
            if (isFinal) {
                firstSegmentPending[outputStreamId] = true
                val out = buf.toByteArray()
                buf.reset()
                return@synchronized if (out.isEmpty()) null else out
            }
            // 2) 首段优先：仅当 leg 处于 pending 状态（首次 utterance 起始或 isFinal 重置后）。
            val pending = firstSegmentPending.getOrDefault(outputStreamId, true)
            if (pending) {
                val firstFlushBytes = (sampleRateHz * 2 * FIRST_SEGMENT_FLUSH_MS / 1000L).toInt()
                if (buf.size() >= firstFlushBytes) {
                    firstSegmentPending[outputStreamId] = false
                    val out = buf.toByteArray()
                    buf.reset()
                    Log.d(TAG, "firstSegmentFlush: leg=$outputStreamId bytes=${out.size}")
                    return@synchronized if (out.isEmpty()) null else out
                }
            }
            null
        }
        if (pendingFlush != null) {
            encodeAndDispatchAsync(source, outputStreamId, pendingFlush)
        }
        return true
    }

    private fun encodeAndDispatchAsync(source: Int, leg: String, pcmBytes: ByteArray) {
        val seq = synchronized(bufferLock) { ++encodeSeq }
        val pcmFile = File(tempDir, "tts_${source}_$seq.pcm")
        val opusFile = File(tempDir, "tts_${source}_$seq.opus")
        try {
            pcmFile.writeBytes(pcmBytes)
        } catch (e: Throwable) {
            Log.w(TAG, "encodeAndDispatch leg=$leg seq=$seq write pcm file failed: ${e.message}")
            return
        }
        // OpusManager.encodeFile(in, out, callback) 默认 OpusOption（带 head），与 demo 一致。
        val encoder = OpusManager()
        encoder.encodeFile(pcmFile.absolutePath, opusFile.absolutePath, object : OnStateCallback {
            override fun onStart() {}
            override fun onComplete(path: String?) {
                try {
                    val opusBytes = if (opusFile.exists()) opusFile.readBytes() else null
                    if (opusBytes == null || opusBytes.isEmpty()) {
                        Log.w(TAG, "encodeAndDispatch leg=$leg seq=$seq: empty opus output")
                    } else {
                        Log.d(TAG, "encodeAndDispatch leg=$leg seq=$seq pcm=${pcmBytes.size}B opus=${opusBytes.size}B")
                        writeBack(AudioData(source, Constants.AUDIO_TYPE_OPUS, opusBytes))
                    }
                } finally {
                    runCatching { encoder.release() }
                    runCatching { pcmFile.delete() }
                    runCatching { opusFile.delete() }
                }
            }
            override fun onError(code: Int, message: String?) {
                Log.w(TAG, "encodeAndDispatch leg=$leg seq=$seq encodeFile error code=$code msg=$message")
                runCatching { encoder.release() }
                runCatching { pcmFile.delete() }
                runCatching { opusFile.delete() }
                onError(code, "encodeFile $leg: $message")
            }
        })
    }

    fun stop() {
        runCatching { flushWatcher?.shutdownNow() }
        flushWatcher = null
        runCatching {
            translationImpl.exitMode(object : OnRcspActionCallback<Int> {
                override fun onSuccess(d: BluetoothDevice?, t: Int?) {}
                override fun onError(d: BluetoothDevice?, err: com.jieli.bluetooth.bean.base.BaseError?) {}
            })
        }
        runCatching { translationImpl.removeTranslationCallback(translationCallback) }
        runCatching { translationImpl.destroy() }
        runCatching { upDecoder?.stop() }
        runCatching { downDecoder?.stop() }
        runCatching { stereoDecoder?.stop() }
        runCatching {
            uplinkWriter.clear()
            downlinkWriter.clear()
            phoneMicWriter.clear()
            rawWriter.clear()
        }
        synchronized(bufferLock) {
            pcmBuffers.values.forEach { it.reset() }
            pcmBuffers.clear()
            firstSegmentPending.clear()
        }
    }

    /**
     * 把 OPUS / PCM 帧入队到对应 source 的 [WriteScheduler]，由调度器串行发起 RCSP
     * writeAudioData，避免并发写入触发 "Operation in progress"。
     */
    private fun writeBack(data: AudioData) {
        val scheduler = when (data.source) {
            AudioData.SOURCE_E_SCO_UP_LINK -> uplinkWriter
            AudioData.SOURCE_E_SCO_DOWN_LINK -> downlinkWriter
            AudioData.SOURCE_PHONE_MIC -> phoneMicWriter
            else -> rawWriter
        }
        scheduler.enqueue(data)
    }
}
