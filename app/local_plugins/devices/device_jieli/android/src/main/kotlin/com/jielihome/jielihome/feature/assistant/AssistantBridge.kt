package com.jielihome.jielihome.feature.assistant

import android.util.Log
import com.aiagent.device_plugin_interface.AssistantAudioFormat
import com.jielihome.jielihome.bridge.EventDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import java.util.concurrent.atomic.AtomicLong

/**
 * Flutter ↔ [JieliAssistantPort] 的桥接。把 SharedFlow 形态的音频帧 / 错误流
 * 转成 [EventDispatcher] 事件（`assistantAudio` / `assistantError`），让
 * Dart 侧可以通过 EventChannel 实时收到耳机麦上行的 16 kHz PCM。
 *
 * `start` 内部调用 [JieliAssistantPort.enter]（`MODE_RECORD` +
 * `STRATEGY_DEVICE_ALWAYS_RECORDING`），耳机会持续推 OPUS，由 Port 解码成
 * 16 kHz/16 bit/mono/20 ms PCM。`stop` 调用 [JieliAssistantPort.exit] 并
 * 取消订阅。两者通过 `synchronized` 互斥，重复调用安全。
 */
class AssistantBridge(
    private val port: JieliAssistantPort,
    private val dispatcher: EventDispatcher,
) {

    companion object {
        private const val TAG = "AssistantBridge"
    }

    private val scopeJob = SupervisorJob()
    private val scope = CoroutineScope(Dispatchers.IO + scopeJob)

    @Volatile private var audioJob: Job? = null
    @Volatile private var errorJob: Job? = null
    @Volatile private var running = false

    /** 调试：每秒打一次 PCM 转发统计，方便确认音频是否真正流到 Dart */
    private val fwdCount = AtomicLong(0)
    @Volatile private var lastReportMs = 0L

    @Synchronized
    fun start(): Boolean {
        if (running) {
            Log.w(TAG, "start: already running, ignored")
            return true
        }

        // 先订阅 Flow，再 enter()，避免首帧落在订阅者建立之前被 SharedFlow 丢掉
        // （JieliAssistantPort 用 replay=0 + DROP_OLDEST）
        audioJob = port.audioFrames.onEach { frame ->
            fwdCount.incrementAndGet()
            val now = System.currentTimeMillis()
            if (now - lastReportMs >= 1000L) {
                Log.i(
                    TAG,
                    "fwd PCM stats (last 1s): frames=${fwdCount.getAndSet(0)} bytes/frame=${frame.bytes.size} sr=${frame.sampleRate}",
                )
                lastReportMs = now
            }
            dispatcher.send(
                mapOf(
                    "type" to "assistantAudio",
                    "encoding" to "pcm16",
                    "sampleRate" to frame.sampleRate,
                    "channels" to frame.channels,
                    "bitsPerSample" to 16,
                    "sequence" to frame.sequence,
                    "tsMs" to (frame.timestampUs / 1000L),
                    "pcm" to frame.bytes,
                )
            )
        }.launchIn(scope)

        errorJob = port.errors.onEach { err ->
            Log.w(TAG, "port.error code=${err.code} msg=${err.message}")
            dispatcher.send(
                mapOf(
                    "type" to "assistantError",
                    "code" to err.code,
                    "message" to err.message,
                )
            )
        }.launchIn(scope)

        try {
            port.enter(AssistantAudioFormat.PCM_S16LE_16K_MONO_20MS)
        } catch (t: Throwable) {
            Log.e(TAG, "start: port.enter failed: ${t.message}", t)
            runCatching { audioJob?.cancel() }
            runCatching { errorJob?.cancel() }
            audioJob = null
            errorJob = null
            dispatcher.send(
                mapOf(
                    "type" to "assistantError",
                    "code" to "device.assistant.enter_failed",
                    "message" to (t.message ?: t.javaClass.simpleName),
                )
            )
            return false
        }

        running = true
        dispatcher.send(
            mapOf(
                "type" to "assistantStart",
                "sampleRate" to 16000,
                "tsMs" to System.currentTimeMillis(),
            )
        )
        Log.i(TAG, "start: assistant port entered, audio bridge active")
        return true
    }

    @Synchronized
    fun stop() {
        if (!running) return
        running = false
        runCatching { audioJob?.cancel() }
        runCatching { errorJob?.cancel() }
        audioJob = null
        errorJob = null
        runCatching { port.exit() }
        dispatcher.send(
            mapOf(
                "type" to "assistantEnd",
                "tsMs" to System.currentTimeMillis(),
            )
        )
        Log.i(TAG, "stop: assistant port exited, audio bridge inactive")
    }

    fun isRunning(): Boolean = running

    fun shutdown() {
        stop()
        runCatching { scope.cancel() }
    }
}
