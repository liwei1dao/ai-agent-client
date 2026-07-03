package com.aiagent.assistant_server

import android.content.Context
import android.util.Log
import com.aiagent.device_plugin_interface.AssistantAudioCodec
import com.aiagent.device_plugin_interface.AssistantAudioFormat
import com.aiagent.device_plugin_interface.AssistantPlaybackFrame
import com.aiagent.device_plugin_interface.DeviceAssistantPort
import com.aiagent.plugin_interface.ExternalAudioFormat
import com.aiagent.plugin_interface.ExternalAudioFrame
import com.aiagent.plugin_interface.ExternalAudioSink
import com.aiagent.plugin_interface.NativeAgent
import com.aiagent.plugin_interface.NativeAgentConfig
import com.aiagent.plugin_interface.NativeAgentRegistry
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.collect

/**
 * 一个活跃的 AI 助理会话。
 *
 * 通过 vendor-agnostic 的 [DeviceAssistantPort] 打通设备 PCM 上下行：
 *  - 上行：[DeviceAssistantPort.audioFrames] → chat agent `pushExternalAudioFrame`；
 *  - 下行：chat agent TTS PCM → [DeviceAssistantPort.reportPlayback] 回灌耳机扬声器。
 *
 * 生命周期：starting → active → stopping → stopped/error。
 */
internal class AssistantSession(
    val sessionId: String,
    private val context: Context,
    private val request: AssistantRequest,
    private val emit: (Map<String, Any?>) -> Unit,
) {
    companion object {
        private const val TAG = "AssistantSession"
        private const val CONNECT_TIMEOUT_MS = 10_000L
    }

    enum class State { STARTING, ACTIVE, STOPPING, STOPPED, ERROR }

    @Volatile var state: State = State.STARTING
        private set

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private var agent: NativeAgent? = null
    private var devicePort: DeviceAssistantPort? = null

    /** 启动整条管道；失败抛出（调用方负责 emit error）。 */
    suspend fun start() {
        // 1. 找设备端口（vendor-agnostic AI 助理端口）
        val port = DevicePortLocator.activeAssistantPort()
            ?: throw IllegalStateException("assistant.no_device: no active assistant port")
        devicePort = port

        // 2. 创建 chat agent 实例
        val a = NativeAgentRegistry.create(request.agentType)
        agent = a

        val sink = AssistantSinkAdapter(sessionId, emit)
        a.initialize(request.agentConfig, sink, context)

        // 3. chat agent connectService 立即上报 ready；保留 timeout 兜底以防未来变更
        a.connectService()
        try {
            withTimeout(CONNECT_TIMEOUT_MS) {
                sink.connected.await()
            }
        } catch (e: TimeoutCancellationException) {
            throw IllegalStateException(
                "assistant.connect_timeout: agent connect timeout after ${CONNECT_TIMEOUT_MS}ms"
            )
        }

        // 4. 协商外部音频格式：PCM_S16LE / 16k / mono / 20ms
        val format = ExternalAudioFormat.PCM_S16LE_16K_MONO_20MS
        val cap = a.externalAudioCapability()
        if (!cap.acceptsPcm) {
            throw IllegalStateException(
                "assistant.agent_unsupported: agent doesn't accept PCM external audio"
            )
        }

        // 5. 启动外部音频源 + 注入 TTS 反向 sink（回灌耳机扬声器）
        a.startExternalAudio(format, ttsSink(port))

        // 6. enter device port —— 此后耳机帧开始派发到 audioFrames flow
        port.enter(AssistantAudioFormat.PCM_S16LE_16K_MONO_20MS)

        // 7. 启动两条独立的 collect 协程
        scope.launch { pumpAudioFrames(port) }
        scope.launch { pumpDeviceErrors(port) }

        state = State.ACTIVE
        emit(AssistantEvents.sessionState(sessionId, "active"))
        Log.d(TAG, "session=$sessionId active")
    }

    private suspend fun pumpAudioFrames(port: DeviceAssistantPort) {
        try {
            var upCount = 0L
            var lastReportMs = System.currentTimeMillis()
            port.audioFrames.collect { frame ->
                upCount++
                val now = System.currentTimeMillis()
                if (now - lastReportMs >= 1000L) {
                    Log.d(TAG, "pump stats (last 1s): up=$upCount")
                    upCount = 0; lastReportMs = now
                }
                agent?.pushExternalAudioFrame(frame.bytes)
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.e(TAG, "pumpAudioFrames error", e)
            emit(AssistantEvents.error(
                sessionId, "assistant.pump_failed", e.message ?: "unknown", fatal = true,
            ))
            stop()
        }
    }

    private suspend fun pumpDeviceErrors(port: DeviceAssistantPort) {
        port.errors.collect { err ->
            // device 错误默认非致命
            emit(AssistantEvents.error(sessionId, err.code, err.message))
        }
    }

    private fun ttsSink(port: DeviceAssistantPort) =
        object : ExternalAudioSink {
            override fun onTtsFrame(frame: ExternalAudioFrame) {
                if (frame.codec != ExternalAudioFormat.Codec.PCM_S16LE) {
                    Log.w(TAG, "tts frame codec ${frame.codec} not supported by device port; dropped")
                    return
                }
                runCatching {
                    port.reportPlayback(
                        AssistantPlaybackFrame(
                            codec = AssistantAudioCodec.PCM_S16LE,
                            sampleRate = frame.sampleRate,
                            channels = frame.channels,
                            bytes = frame.bytes,
                            isFinal = frame.isFinal,
                        )
                    )
                }.onFailure {
                    Log.w(TAG, "reportPlayback failed: ${it.message}")
                }
            }

            override fun onError(code: String, message: String) {
                emit(AssistantEvents.error(sessionId, code, message))
            }
        }

    /** 停止会话，释放所有资源。幂等。 */
    fun stop() {
        if (state == State.STOPPED || state == State.STOPPING) return
        state = State.STOPPING
        emit(AssistantEvents.sessionState(sessionId, "stopping"))
        Log.d(TAG, "session=$sessionId stopping")

        runCatching { devicePort?.exit() }
        runCatching { agent?.stopExternalAudio() }
        runCatching { agent?.disconnectService() }
        runCatching { agent?.release() }

        scope.cancel()
        agent = null
        devicePort = null

        state = State.STOPPED
        emit(AssistantEvents.sessionState(sessionId, "stopped"))
        Log.d(TAG, "session=$sessionId stopped")
    }

    fun markError(code: String, message: String) {
        if (state == State.STOPPED || state == State.ERROR) return
        emit(AssistantEvents.error(sessionId, code, message, fatal = true))
        emit(AssistantEvents.sessionState(sessionId, "error", message))
        runCatching { stop() }
        state = State.ERROR
    }
}

/** startAssistant 入参。 */
internal data class AssistantRequest(
    val agentType: String,
    val agentConfig: NativeAgentConfig,
    val userLanguage: String,
)
