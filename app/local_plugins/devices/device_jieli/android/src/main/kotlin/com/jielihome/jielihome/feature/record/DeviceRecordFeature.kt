package com.jielihome.jielihome.feature.record

import com.jielihome.jielihome.bridge.EventDispatcher
import com.jielihome.jielihome.core.JieliHomeServer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach

/**
 * 设备录音功能（MethodChannel/EventChannel 适配层）。
 *
 * 实现下沉到 [JieliDeviceRecordPort]：MODE_CALL_RECORD(=7)
 * + STRATEGY_DEVICE_ALWAYS_RECORDING + 双声道 OPUS（SOURCE_E_SCO_MIX）。耳机
 * 持续上推 stereo OPUS，Port 解码成 16k/16bit/stereo 交织 PCM；本类把 Flow
 * 事件转发到 [EventDispatcher] 给 Dart 侧。
 *
 * 事件类型：
 *   - `deviceRecordStart`  — 上行启动成功（payload: address, sampleRate, tsMs）
 *   - `deviceRecordAudio`  — PCM 帧
 *       payload: address, streamId="in.stereo", sampleRate, channels=2,
 *                bitsPerSample=16, tsMs, pcm(ByteArray, 交织 LR)
 *   - `deviceRecordStop`   — 上行已停止
 *   - `deviceRecordError`  — 错误
 *
 * 与 [com.jielihome.jielihome.feature.translation.TranslationFeature] 互斥：
 * 两者都调用 SDK enterMode，同时只能有一个活跃。
 * 调用方（MethodRouter）负责在启动前 stop 另一个。
 */
class DeviceRecordFeature(
    private val server: JieliHomeServer,
) {
    private val dispatcher: EventDispatcher get() = server.dispatcher

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    @Volatile private var audioJob: Job? = null
    @Volatile private var errorJob: Job? = null
    @Volatile private var working = false
    @Volatile private var deviceAddress: String? = null

    fun isRecording(): Boolean = working

    /**
     * 启动设备录音上行。
     *
     * @param args 可选参数：
     *   - `address`    String  目标设备 MAC；省略则取当前已连设备
     *   - `sampleRate` Int     采样率（Hz），默认 16000
     */
    fun start(args: Map<String, Any?>): Result<Unit> {
        if (working) return Result.failure(IllegalStateException("already recording"))

        val address = args["address"] as? String
        val sampleRate = (args["sampleRate"] as? Int) ?: 16000

        // 解析地址用于 deviceRecordStart/Stop 事件携带（即使 args.address 省略，也要把
        // 实际连接到的设备地址回传给 Dart，便于上层做多设备路由）
        val device = address?.let { server.connectFeature.deviceByAddress(it) }
            ?: server.connectFeature.connectedDevice()
            ?: return Result.failure(
                IllegalStateException("no connected device; pass args.address or connect first")
            )
        val resolvedAddress = device.address

        val port = server.deviceRecordPort

        // 先订阅再 start，避免首帧落在订阅建立之前被 SharedFlow 丢掉（replay=0）
        audioJob = port.audioFrames.onEach { f ->
            dispatcher.send(
                mapOf(
                    "type"          to "deviceRecordAudio",
                    "address"       to f.address,
                    "streamId"      to f.streamId,
                    "sampleRate"    to f.sampleRate,
                    "channels"      to f.channels,
                    "bitsPerSample" to f.bitsPerSample,
                    "tsMs"          to f.tsMs,
                    "pcm"           to f.pcm,
                )
            )
        }.launchIn(scope)

        errorJob = port.errors.onEach { e ->
            dispatcher.send(
                mapOf(
                    "type"    to "deviceRecordError",
                    "address" to e.address,
                    "code"    to e.code,
                    "message" to e.message,
                )
            )
        }.launchIn(scope)

        return port.start(address = resolvedAddress, sampleRate = sampleRate).fold(
            onSuccess = {
                working = true
                deviceAddress = resolvedAddress
                dispatcher.send(
                    mapOf(
                        "type"       to "deviceRecordStart",
                        "address"    to resolvedAddress,
                        "sampleRate" to sampleRate,
                        "tsMs"       to System.currentTimeMillis(),
                    )
                )
                Result.success(Unit)
            },
            onFailure = { err ->
                runCatching { audioJob?.cancel() }
                runCatching { errorJob?.cancel() }
                audioJob = null
                errorJob = null
                Result.failure(err)
            },
        )
    }

    /** 停止设备录音上行。幂等：未录音时无副作用。 */
    fun stop() {
        if (!working) return
        working = false
        val addr = deviceAddress
        deviceAddress = null
        runCatching { audioJob?.cancel() }
        runCatching { errorJob?.cancel() }
        audioJob = null
        errorJob = null
        runCatching { server.deviceRecordPort.stop() }
        dispatcher.send(
            mapOf(
                "type"    to "deviceRecordStop",
                "address" to addr,
                "tsMs"    to System.currentTimeMillis(),
            )
        )
    }
}
