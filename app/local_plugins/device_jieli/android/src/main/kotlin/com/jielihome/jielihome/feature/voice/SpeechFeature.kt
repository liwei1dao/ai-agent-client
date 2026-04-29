package com.jielihome.jielihome.feature.voice

import android.bluetooth.BluetoothDevice
import com.jieli.bluetooth.bean.base.BaseError
import com.jieli.bluetooth.bean.record.RecordParam
import com.jieli.bluetooth.bean.record.RecordState
import com.jieli.bluetooth.impl.JL_BluetoothManager
import com.jieli.bluetooth.impl.rcsp.record.RecordOpImpl
import com.jieli.bluetooth.interfaces.rcsp.callback.OnRcspActionCallback
import com.jieli.bluetooth.interfaces.rcsp.record.OnRecordStateCallback
import com.jielihome.jielihome.audio.OpusStreamDecoder
import com.jielihome.jielihome.bridge.EventDispatcher
import com.jielihome.jielihome.feature.ConnectFeature

/**
 * 语音助手 / 唤醒功能。
 *
 * # 工作模型（重要）
 * 唤醒是「**耳机端主动检测 + 主动推**」模式。零等待：
 *
 *   1. 插件初始化时立即注册一个常驻 [OnRecordStateCallback]（[attach]）
 *   2. 耳机本地检测到唤醒词 / 用户按下语音键
 *      → SDK 直接回调 onStateChange(state=START)，**不需要 APP 先发任何指令**
 *      → 紧接着持续回调 state=WORKING + voiceData（PCM 或 OPUS 帧）
 *      → 通话结束/取消时回调 state=IDLE
 *   3. 插件解码后通过 EventDispatcher 推三类事件给宿主：
 *      `speechStart` / `speechAudio` / `speechEnd`
 *
 * # 主动控制（可选）
 *   - [start]：APP 主动触发语音助手（用户点 UI 的"按住说话"按钮场景）
 *   - [stop]：APP 主动结束（用户松手 / 超时取消）
 *   - 这两个调用内部封装了 SDK 的 StartSpeechCmd/StopSpeechCmd。
 *     大部分场景下你不需要调它们——耳机会自动管理。
 */
class SpeechFeature(
    private val btManager: JL_BluetoothManager,
    private val connectFeature: ConnectFeature,
    private val dispatcher: EventDispatcher,
) {
    private val recordOp: RecordOpImpl = RecordOpImpl.getInstance(btManager)

    @Volatile
    private var decoder: OpusStreamDecoder? = null

    @Volatile
    private var currentParam: RecordParam? = null

    private val recordCallback = OnRecordStateCallback { device, state ->
        if (device == null || state == null) return@OnRecordStateCallback
        when (state.state) {
            RecordState.RECORD_STATE_START -> onStart(device, state)
            RecordState.RECORD_STATE_WORKING -> onWorking(device, state)
            RecordState.RECORD_STATE_IDLE -> onEnd(device, state)
        }
    }

    fun attach() {
        recordOp.addOnRecordStateCallback(recordCallback)
    }

    fun detach() {
        recordOp.removeOnRecordStateCallback(recordCallback)
        releaseDecoder()
    }

    fun isRecording(address: String?): Boolean {
        val d = address?.let { connectFeature.deviceByAddress(it) }
            ?: connectFeature.connectedDevice() ?: return false
        return recordOp.isRecording(d)
    }

    /**
     * APP 主动启动语音助手；通常无需调用（耳机会自动推）。
     * @param voiceType  RecordParam.VOICE_TYPE_PCM / SPEEX / OPUS
     * @param sampleRate RecordParam.SAMPLE_RATE_8K / 16K（注意取值是 8/16，不是 8000/16000）
     * @param vadWay     RecordParam.VAD_WAY_DEVICE / SDK
     */
    fun start(
        address: String?,
        voiceType: Int = RecordParam.VOICE_TYPE_OPUS,
        sampleRate: Int = RecordParam.SAMPLE_RATE_16K,
        vadWay: Int = RecordParam.VAD_WAY_DEVICE,
        onResult: (ok: Boolean, msg: String?) -> Unit = { _, _ -> },
    ) {
        val device = address?.let { connectFeature.deviceByAddress(it) }
            ?: connectFeature.connectedDevice()
            ?: return onResult(false, "no connected device")
        val param = RecordParam(voiceType, sampleRate, vadWay)
        recordOp.startRecord(device, param, object : OnRcspActionCallback<Boolean> {
            override fun onSuccess(d: BluetoothDevice?, r: Boolean?) { onResult(r == true, null) }
            override fun onError(d: BluetoothDevice?, e: BaseError?) { onResult(false, e?.message) }
        })
    }

    fun stop(
        address: String?,
        reason: Int = RecordState.REASON_NORMAL,
        onResult: (ok: Boolean, msg: String?) -> Unit = { _, _ -> },
    ) {
        val device = address?.let { connectFeature.deviceByAddress(it) }
            ?: connectFeature.connectedDevice()
            ?: return onResult(false, "no connected device")
        recordOp.stopRecord(device, reason, object : OnRcspActionCallback<Boolean> {
            override fun onSuccess(d: BluetoothDevice?, r: Boolean?) { onResult(r == true, null) }
            override fun onError(d: BluetoothDevice?, e: BaseError?) { onResult(false, e?.message) }
        })
    }

    // ───── 内部回调处理 ─────

    private fun onStart(device: BluetoothDevice, state: RecordState) {
        currentParam = state.recordParam
        ensureDecoder(state.recordParam)
        dispatcher.send(
            mapOf(
                "type" to "speechStart",
                "address" to device.address,
                "voiceType" to state.recordParam?.voiceType,
                "sampleRate" to (state.recordParam?.sampleRate ?: 16) * 1000, // 8/16 → 8000/16000
                "vadWay" to state.recordParam?.vadWay,
                "tsMs" to System.currentTimeMillis(),
            )
        )
    }

    private fun onWorking(device: BluetoothDevice, state: RecordState) {
        val payload = state.voiceDataBlock ?: state.voiceData ?: return
        val type = (state.recordParam ?: currentParam)?.voiceType ?: RecordParam.VOICE_TYPE_OPUS
        when (type) {
            RecordParam.VOICE_TYPE_OPUS -> decoder?.feedEncoded(payload) ?: emitFrame(device, payload)
            RecordParam.VOICE_TYPE_PCM -> emitFrame(device, payload)
            RecordParam.VOICE_TYPE_SPEEX -> {
                // 当前未挂 speex 解码器；原样透出，由宿主自己解（极少使用）
                emitFrame(device, payload, encoding = "speex")
            }
        }
    }

    private fun onEnd(device: BluetoothDevice, state: RecordState) {
        releaseDecoder()
        dispatcher.send(
            mapOf(
                "type" to "speechEnd",
                "address" to device.address,
                "reason" to state.reason,
                "message" to state.message,
                "tsMs" to System.currentTimeMillis(),
            )
        )
        currentParam = null
    }

    private fun ensureDecoder(param: RecordParam?) {
        if (decoder != null) return
        if (param?.voiceType != RecordParam.VOICE_TYPE_OPUS) return
        val srKhz = param.sampleRate.takeIf { it > 0 } ?: RecordParam.SAMPLE_RATE_16K
        val sampleRateHz = srKhz * 1000
        val packetSize = if (srKhz == RecordParam.SAMPLE_RATE_8K) 50 else 200
        decoder = OpusStreamDecoder(
            channel = 1,
            packetSize = packetSize,
            sampleRate = sampleRateHz,
            onPcm = { pcm -> emitFrame(connectFeature.connectedDevice(), pcm) },
            onError = { c, m ->
                dispatcher.send(
                    mapOf("type" to "speechError", "code" to c, "message" to "decoder: $m")
                )
            }
        ).also { it.start() }
    }

    private fun releaseDecoder() {
        runCatching { decoder?.stop() }
        decoder = null
    }

    private fun emitFrame(
        device: BluetoothDevice?,
        pcm: ByteArray,
        encoding: String = "pcm16",
    ) {
        val sr = (currentParam?.sampleRate ?: RecordParam.SAMPLE_RATE_16K) * 1000
        dispatcher.send(
            mapOf(
                "type" to "speechAudio",
                "address" to device?.address,
                "encoding" to encoding,
                "sampleRate" to sr,
                "channels" to 1,
                "bitsPerSample" to 16,
                "tsMs" to System.currentTimeMillis(),
                "pcm" to pcm,
            )
        )
    }
}
