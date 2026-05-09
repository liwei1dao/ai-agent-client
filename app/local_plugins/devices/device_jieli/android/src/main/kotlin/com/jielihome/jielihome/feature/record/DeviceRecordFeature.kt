package com.jielihome.jielihome.feature.record

import android.content.Context
import com.jieli.bluetooth.bean.translation.AudioData
import com.jieli.bluetooth.bean.translation.TranslationMode
import com.jieli.bluetooth.constant.Constants
import com.jieli.bluetooth.impl.JL_BluetoothManager
import com.jielihome.jielihome.bridge.EventDispatcher
import com.jielihome.jielihome.feature.ConnectFeature
import com.jielihome.jielihome.feature.translation.runtime.RcspTranslationRuntime
import java.io.File

/**
 * 设备录音功能。
 *
 * 通过 RCSP [TranslationMode.MODE_CALL_TRANSLATION] + STRATEGY_DEVICE_ALWAYS_RECORDING
 * 让耳机持续上推双通道 PCM：
 *   - [AudioData.SOURCE_E_SCO_UP_LINK]   → streamId = "in.uplink"   （本端/耳机麦克风）
 *   - [AudioData.SOURCE_E_SCO_DOWN_LINK] → streamId = "in.downlink" （对端/通话对方）
 *
 * 事件类型：
 *   - `deviceRecordStart`  — 上行启动成功
 *   - `deviceRecordAudio`  — PCM 帧（含 streamId 区分上下行）
 *   - `deviceRecordStop`   — 上行已停止
 *   - `deviceRecordError`  — 错误
 *
 * 与 [com.jielihome.jielihome.feature.translation.TranslationFeature] 互斥：
 * 两者都调用 SDK enterMode，同时只能有一个活跃。
 * 调用方（MethodRouter）负责在启动前 stop 另一个。
 */
class DeviceRecordFeature(
    private val context: Context,
    private val btManager: JL_BluetoothManager,
    private val connectFeature: ConnectFeature,
    private val dispatcher: EventDispatcher,
) {
    @Volatile private var runtime: RcspTranslationRuntime? = null
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
        val device = address?.let { connectFeature.deviceByAddress(it) }
            ?: connectFeature.connectedDevice()
            ?: return Result.failure(IllegalStateException("no connected device; pass args.address or connect first"))

        val sampleRate = (args["sampleRate"] as? Int) ?: 16000

        val sdkMode = TranslationMode(
            TranslationMode.MODE_CALL_TRANSLATION,
            Constants.AUDIO_TYPE_OPUS,
            1,
            sampleRate,
        ).setRecordingStrategy(TranslationMode.STRATEGY_DEVICE_ALWAYS_RECORDING)

        val rt = RcspTranslationRuntime(
            btManager = btManager,
            device = device,
            mode = sdkMode,
            tempDir = File(context.cacheDir, "jieli_device_record_tmp"),
            onPcm = { source, pcm ->
                val streamId = when (source) {
                    AudioData.SOURCE_E_SCO_UP_LINK   -> "in.uplink"
                    AudioData.SOURCE_E_SCO_DOWN_LINK -> "in.downlink"
                    else -> return@RcspTranslationRuntime
                }
                dispatcher.send(
                    mapOf(
                        "type"          to "deviceRecordAudio",
                        "address"       to device.address,
                        "streamId"      to streamId,
                        "sampleRate"    to sampleRate,
                        "channels"      to 1,
                        "bitsPerSample" to 16,
                        "tsMs"          to System.currentTimeMillis(),
                        "pcm"           to pcm,
                    )
                )
            },
            onError = { code, msg ->
                dispatcher.send(
                    mapOf(
                        "type"    to "deviceRecordError",
                        "address" to device.address,
                        "code"    to code,
                        "message" to msg,
                    )
                )
            },
        )

        return rt.start().fold(
            onSuccess = {
                runtime = rt
                working = true
                deviceAddress = device.address
                dispatcher.send(
                    mapOf(
                        "type"       to "deviceRecordStart",
                        "address"    to device.address,
                        "sampleRate" to sampleRate,
                        "tsMs"       to System.currentTimeMillis(),
                    )
                )
                Result.success(Unit)
            },
            onFailure = { err ->
                rt.stop()
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
        runtime?.stop()
        runtime = null
        dispatcher.send(
            mapOf(
                "type"    to "deviceRecordStop",
                "address" to addr,
                "tsMs"    to System.currentTimeMillis(),
            )
        )
    }
}
