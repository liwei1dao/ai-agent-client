package com.jielihome.jielihome.feature.record

import android.util.Log
import com.jielihome.jielihome.api.JieliEventAdapter
import com.jielihome.jielihome.core.JieliHomeServer
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow

/** 录音音频帧（已解码为 PCM_S16LE）。*/
data class DeviceRecordFrame(
    val address: String,
    /** [DeviceRecordFeature] 的 "in.uplink"（本端）或 "in.downlink"（对端）*/
    val streamId: String,
    val pcm: ByteArray,
    val sampleRate: Int,
    val channels: Int = 1,
    val bitsPerSample: Int = 16,
    val tsMs: Long,
) {
    // ByteArray 默认 equals/hashCode 按内容比，这里改为引用比避免大帧逐字节比
    override fun equals(other: Any?): Boolean = this === other
    override fun hashCode(): Int = System.identityHashCode(this)
}

/** 录音错误。 */
data class DeviceRecordError(val address: String?, val code: Int, val message: String?)

/**
 * 设备录音端口 —— 原生层编排器的直连入口。
 *
 * 与 [com.jielihome.jielihome.feature.translation.JieliCallTranslationPort] 对称：
 *   - [start] 启动耳机音频上行
 *   - [audioFrames] 是 Kotlin Flow，收集即可获取上行/下行 PCM 帧
 *   - [stop] 停止上行
 *
 * Flutter 路径（EventChannel）不受影响：同一帧会同时推给 native flow 和 Dart EventChannel。
 *
 * # 典型用法
 * ```kotlin
 * val port = server.deviceRecordPort
 * val job = scope.launch {
 *     port.audioFrames.collect { frame ->
 *         // frame.streamId == "in.uplink" → 本端说话
 *         // frame.streamId == "in.downlink" → 对端说话
 *         writeToFile(frame.streamId, frame.pcm)
 *     }
 * }
 * port.start(address = device.address)
 * // ...
 * port.stop()
 * job.cancel()
 * ```
 *
 * # 生命周期
 * Port 是 [JieliHomeServer] 的懒加载单例（`server.deviceRecordPort`），
 * 与 server 共存亡，无需手动 [release]。若在 server 生命周期外独立使用则需调 [release]。
 */
class JieliDeviceRecordPort(
    private val server: JieliHomeServer,
) {
    companion object {
        private const val TAG = "JieliDeviceRecordPort"

        const val STREAM_UPLINK = "in.uplink"
        const val STREAM_DOWNLINK = "in.downlink"
    }

    private val _audioFrames = MutableSharedFlow<DeviceRecordFrame>(
        replay = 0,
        extraBufferCapacity = 256,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )
    private val _errors = MutableSharedFlow<DeviceRecordError>(
        replay = 0,
        extraBufferCapacity = 16,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )

    /** 录音 PCM 帧流。每帧包含 streamId 区分上行/下行。 */
    val audioFrames: Flow<DeviceRecordFrame> = _audioFrames.asSharedFlow()

    /** 错误流。 */
    val errors: Flow<DeviceRecordError> = _errors.asSharedFlow()

    val isRecording: Boolean get() = server.deviceRecordFeature.isRecording()

    private val eventListener = object : JieliEventAdapter() {
        override fun onDeviceRecordAudio(payload: Map<String, Any?>) {
            val address = payload["address"] as? String ?: return
            val streamId = payload["streamId"] as? String ?: return
            val pcm = payload["pcm"] as? ByteArray ?: return
            val sampleRate = (payload["sampleRate"] as? Number)?.toInt() ?: 16000
            val channels = (payload["channels"] as? Number)?.toInt() ?: 1
            val bitsPerSample = (payload["bitsPerSample"] as? Number)?.toInt() ?: 16
            val tsMs = (payload["tsMs"] as? Number)?.toLong() ?: System.currentTimeMillis()
            val frame = DeviceRecordFrame(
                address = address,
                streamId = streamId,
                pcm = pcm,
                sampleRate = sampleRate,
                channels = channels,
                bitsPerSample = bitsPerSample,
                tsMs = tsMs,
            )
            if (!_audioFrames.tryEmit(frame)) {
                Log.w(TAG, "audioFrames buffer overflow; dropped streamId=$streamId")
            }
        }

        override fun onDeviceRecordError(payload: Map<String, Any?>) {
            _errors.tryEmit(
                DeviceRecordError(
                    address = payload["address"] as? String,
                    code = (payload["code"] as? Number)?.toInt() ?: 0,
                    message = payload["message"] as? String,
                )
            )
        }
    }

    init {
        server.addEventListener(eventListener)
    }

    /**
     * 启动设备录音上行。若翻译功能正在运行，会先自动停止。
     *
     * @param address 目标设备 MAC；null 取当前已连设备
     * @param sampleRate 采样率（Hz），默认 16000
     */
    fun start(address: String? = null, sampleRate: Int = 16000): Result<Unit> {
        if (server.translationFeature.isWorking()) server.translationFeature.stop()
        val args = buildMap<String, Any?> {
            if (address != null) put("address", address)
            put("sampleRate", sampleRate)
        }
        return server.deviceRecordFeature.start(args)
    }

    /** 停止设备录音上行。幂等。 */
    fun stop() {
        server.deviceRecordFeature.stop()
    }

    /** 释放事件监听。Port 作为 server 单例使用时无需调用；独立使用时须在不再需要时调用。 */
    fun release() {
        server.removeEventListener(eventListener)
    }
}
