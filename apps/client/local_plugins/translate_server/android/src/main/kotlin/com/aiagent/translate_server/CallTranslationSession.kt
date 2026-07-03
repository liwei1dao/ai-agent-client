package com.aiagent.translate_server

import android.content.Context
import android.util.Log
import com.aiagent.device_plugin_interface.CallAudioFormat
import com.aiagent.device_plugin_interface.CallTranslationLeg
import com.aiagent.device_plugin_interface.DeviceCallTranslationPort
import com.aiagent.device_plugin_interface.TranslatedAudioFrame
import com.aiagent.plugin_interface.ExternalAudioFormat
import com.aiagent.plugin_interface.ExternalAudioFrame
import com.aiagent.plugin_interface.ExternalAudioSink
import com.aiagent.plugin_interface.NativeAgent
import com.aiagent.plugin_interface.NativeAgentConfig
import com.aiagent.plugin_interface.NativeAgentRegistry
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.collect

/**
 * 一个活跃的通话翻译会话。
 *
 * 职责：
 *  1. 创建专属的 uplink/downlink agent 实例（不复用 AgentsServerService 的池）；
 *  2. 等待两端 agent connect 成功后协商外部音频格式（PCM 16k mono 20ms）；
 *  3. enter device port 进入 RCSP 通话翻译模式，开始派发 PCM 帧；
 *  4. 把 device 帧按 leg 路由给对应 agent.pushExternalAudioFrame；
 *  5. agent 出 TTS PCM 通过 [ExternalAudioSink] → device.reportTranslated 回灌耳机；
 *  6. 字幕 / 错误 / 状态通过 [emit] 上报给 Flutter EventChannel。
 *
 * 生命周期：starting → active → stopping → stopped/error。
 * 错误：致命错误（device 进入失败 / 单边 agent connect 失败）→ stop + state=error。
 */
internal class CallTranslationSession(
    val sessionId: String,
    private val context: Context,
    private val request: CallTranslationRequest,
    private val emit: (Map<String, Any?>) -> Unit,
) {
    companion object {
        private const val TAG = "CallTranslationSession"
        private const val CONNECT_TIMEOUT_MS = 10_000L
    }

    enum class State { STARTING, ACTIVE, STOPPING, STOPPED, ERROR }

    @Volatile var state: State = State.STARTING
        private set

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private var uplinkAgent: NativeAgent? = null
    private var downlinkAgent: NativeAgent? = null
    private var devicePort: DeviceCallTranslationPort? = null

    /** 启动整条管道；失败抛出（调用方负责 emit error）。 */
    suspend fun start() {
        // 1. 找设备端口
        val port = DevicePortLocator.activeCallTranslationPort()
            ?: throw IllegalStateException("translate.no_device: no active call translation port")
        devicePort = port

        // 2. 创建两个 agent 实例（用户视角同 id 也 OK——这里是会话内部独立实例）
        val uplink = NativeAgentRegistry.create(request.uplinkAgentType)
        val downlink = NativeAgentRegistry.create(request.downlinkAgentType)
        uplinkAgent = uplink
        downlinkAgent = downlink

        val uplinkSink = AgentSinkAdapter(sessionId, CallLeg.UPLINK, emit)
        val downlinkSink = AgentSinkAdapter(sessionId, CallLeg.DOWNLINK, emit)

        uplink.initialize(request.uplinkConfig, uplinkSink, context)
        downlink.initialize(request.downlinkConfig, downlinkSink, context)

        // 3. 端到端 agent (AST/STS) 需要先 connectService 建链
        uplink.connectService()
        downlink.connectService()
        try {
            withTimeout(CONNECT_TIMEOUT_MS) {
                uplinkSink.connected.await()
                downlinkSink.connected.await()
            }
        } catch (e: TimeoutCancellationException) {
            throw IllegalStateException(
                "translate.connect_timeout: agent connect timeout after ${CONNECT_TIMEOUT_MS}ms"
            )
        }

        // 4. 协商外部音频格式：PCM_S16LE / 16k / mono / 20ms（jieli 端口当前唯一支持）
        val format = ExternalAudioFormat.PCM_S16LE_16K_MONO_20MS
        val uplinkCap = uplink.externalAudioCapability()
        val downlinkCap = downlink.externalAudioCapability()
        if (!uplinkCap.acceptsPcm) {
            throw IllegalStateException(
                "translate.agent_unsupported: uplink agent doesn't accept PCM external audio"
            )
        }
        if (!downlinkCap.acceptsPcm) {
            throw IllegalStateException(
                "translate.agent_unsupported: downlink agent doesn't accept PCM external audio"
            )
        }

        // 5. 启动外部音频源 + 注入 TTS 反向 sink
        uplink.startExternalAudio(format, ttsSink(CallTranslationLeg.UPLINK, port))
        downlink.startExternalAudio(format, ttsSink(CallTranslationLeg.DOWNLINK, port))

        // 6. enter device port —— 此后耳机帧开始派发到 audioFrames flow
        port.enter(CallAudioFormat.PCM_S16LE_16K_MONO_20MS)

        // 7. 启动两条独立的 collect 协程
        scope.launch { pumpAudioFrames(port) }
        scope.launch { pumpDeviceErrors(port) }

        state = State.ACTIVE
        emit(TranslateEvents.sessionState(sessionId, "active"))
        Log.d(TAG, "session=$sessionId active")
    }

    private suspend fun pumpAudioFrames(port: DeviceCallTranslationPort) {
        try {
            // 调试：每秒打一次按 leg 的帧统计，确认 SDK→agent 这段路有没有断。
            var upCount = 0L
            var downCount = 0L
            var lastReportMs = System.currentTimeMillis()
            port.audioFrames.collect { frame ->
                when (frame.leg) {
                    CallTranslationLeg.UPLINK -> upCount++
                    CallTranslationLeg.DOWNLINK -> downCount++
                }
                val now = System.currentTimeMillis()
                if (now - lastReportMs >= 1000L) {
                    Log.d(TAG, "pump stats (last 1s): up=$upCount down=$downCount")
                    upCount = 0; downCount = 0; lastReportMs = now
                }
                val agent = when (frame.leg) {
                    CallTranslationLeg.UPLINK -> uplinkAgent
                    CallTranslationLeg.DOWNLINK -> downlinkAgent
                }
                agent?.pushExternalAudioFrame(frame.bytes)
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.e(TAG, "pumpAudioFrames error", e)
            emit(TranslateEvents.error(
                sessionId, "translate.pump_failed", e.message ?: "unknown", fatal = true,
            ))
            stop()
        }
    }

    private suspend fun pumpDeviceErrors(port: DeviceCallTranslationPort) {
        port.errors.collect { err ->
            // device 错误默认非致命，由调用方决定
            emit(TranslateEvents.error(sessionId, err.code, err.message))
        }
    }

    private fun ttsSink(leg: CallTranslationLeg, port: DeviceCallTranslationPort) =
        object : ExternalAudioSink {
            override fun onTtsFrame(frame: ExternalAudioFrame) {
                if (frame.codec != ExternalAudioFormat.Codec.PCM_S16LE) {
                    Log.w(TAG, "tts frame codec ${frame.codec} not supported by device port; dropped")
                    return
                }
                runCatching {
                    port.reportTranslated(
                        TranslatedAudioFrame(
                            leg = leg,
                            codec = com.aiagent.device_plugin_interface.CallAudioCodec.PCM_S16LE,
                            sampleRate = frame.sampleRate,
                            channels = frame.channels,
                            bytes = frame.bytes,
                            isFinal = frame.isFinal,
                        )
                    )
                }.onFailure {
                    Log.w(TAG, "reportTranslated failed leg=$leg: ${it.message}")
                }
            }

            override fun onError(code: String, message: String) {
                emit(TranslateEvents.error(
                    sessionId, code, message,
                    leg = if (leg == CallTranslationLeg.UPLINK) "uplink" else "downlink",
                ))
            }
        }

    /** 停止会话，释放所有资源。幂等。 */
    fun stop() {
        if (state == State.STOPPED || state == State.STOPPING) return
        state = State.STOPPING
        emit(TranslateEvents.sessionState(sessionId, "stopping"))
        Log.d(TAG, "session=$sessionId stopping")

        runCatching { devicePort?.exit() }
        runCatching { uplinkAgent?.stopExternalAudio() }
        runCatching { downlinkAgent?.stopExternalAudio() }
        runCatching { uplinkAgent?.disconnectService() }
        runCatching { downlinkAgent?.disconnectService() }
        runCatching { uplinkAgent?.release() }
        runCatching { downlinkAgent?.release() }

        scope.cancel()
        uplinkAgent = null
        downlinkAgent = null
        devicePort = null

        state = State.STOPPED
        emit(TranslateEvents.sessionState(sessionId, "stopped"))
        Log.d(TAG, "session=$sessionId stopped")
    }

    fun markError(code: String, message: String) {
        if (state == State.STOPPED || state == State.ERROR) return
        emit(TranslateEvents.error(sessionId, code, message, fatal = true))
        emit(TranslateEvents.sessionState(sessionId, "error", message))
        runCatching { stop() }
        state = State.ERROR
    }
}

/** startCallTranslation 入参。 */
internal data class CallTranslationRequest(
    val uplinkAgentType: String,
    val uplinkConfig: NativeAgentConfig,
    val downlinkAgentType: String,
    val downlinkConfig: NativeAgentConfig,
    val userLanguage: String,
    val peerLanguage: String,
)
