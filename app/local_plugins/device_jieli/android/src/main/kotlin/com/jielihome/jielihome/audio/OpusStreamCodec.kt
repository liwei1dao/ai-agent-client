package com.jielihome.jielihome.audio

import com.jieli.jl_audio_decode.callback.OnDecodeStreamCallback
import com.jieli.jl_audio_decode.callback.OnEncodeStreamCallback
import com.jieli.jl_audio_decode.opus.OpusManager
import com.jieli.jl_audio_decode.opus.model.OpusOption

/**
 * OPUS 流式解码器。
 * 输入：从耳机收到的 OPUS 编码帧
 * 输出：16kHz / mono PCM 流
 *
 * 立体声场景把 [channel] 设 2 + [packetSize] 设 80。
 */
class OpusStreamDecoder(
    private val channel: Int = 1,
    private val packetSize: Int = 200,
    private val sampleRate: Int = 16000,
    private val hasHead: Boolean = false,
    private val onPcm: (pcm: ByteArray) -> Unit,
    private val onError: (code: Int, msg: String?) -> Unit = { _, _ -> },
) {
    private val manager = OpusManager()

    @Volatile
    private var started = false

    fun start() {
        if (started) return
        val option = OpusOption()
            .setHasHead(hasHead)
            .setChannel(channel)
            .setPacketSize(packetSize)
            .setSampleRate(sampleRate)
        manager.startDecodeStream(option, object : OnDecodeStreamCallback {
            override fun onDecodeStream(pcm: ByteArray) { runCatching { onPcm(pcm) } }
            override fun onStart() {}
            override fun onComplete(p0: String?) {}
            override fun onError(code: Int, msg: String?) {
                runCatching { onError(code, msg) }
            }
        })
        started = true
    }

    fun feedEncoded(opus: ByteArray) {
        if (!started) return
        runCatching { manager.writeAudioStream(opus) }
    }

    fun stop() {
        if (!started) return
        runCatching { manager.stopDecodeStream() }
        runCatching { manager.release() }
        started = false
    }
}

/**
 * OPUS 流式编码器。把 PCM 编码成 OPUS 帧后回调 [onOpus]，由调用方包成 AudioData 回送给设备。
 */
class OpusStreamEncoder(
    private val channel: Int = 1,
    private val packetSize: Int = 200,
    private val sampleRate: Int = 16000,
    private val hasHead: Boolean = false,
    private val onOpus: (opus: ByteArray) -> Unit,
    private val onError: (code: Int, msg: String?) -> Unit = { _, _ -> },
) {
    private val manager = OpusManager()

    @Volatile
    private var started = false

    fun start() {
        if (started) return
        val option = OpusOption()
            .setHasHead(hasHead)
            .setChannel(channel)
            .setPacketSize(packetSize)
            .setSampleRate(sampleRate)
        manager.startEncodeStream(option, object : OnEncodeStreamCallback {
            override fun onEncodeStream(opus: ByteArray) { runCatching { onOpus(opus) } }
            override fun onStart() {}
            override fun onComplete(p0: String?) {}
            override fun onError(code: Int, msg: String?) {
                runCatching { onError(code, msg) }
            }
        })
        started = true
    }

    fun feedPcm(pcm: ByteArray) {
        if (!started) return
        runCatching { manager.writeEncodeStream(pcm) }
    }

    fun stop() {
        if (!started) return
        runCatching { manager.stopEncodeStream() }
        runCatching { manager.release() }
        started = false
    }
}
