package com.jielihome.jielihome.feature.translation

import com.jieli.bluetooth.impl.JL_BluetoothManager

/**
 * 翻译模式处理器统一接口。每种模式独立实现：
 *  - 声明自己消费哪些「输入流」（采集面）和产出哪些「输出流」（回放面）
 *  - 实现 start：启动 SDK 端音频流（进入翻译模式 / 起手机麦），把解码后的 PCM 通过 bridge 推出
 *  - 实现 stop：关闭音频流，释放编解码器
 *  - 实现 onTranslatedAudio：接到外部翻译服务回送的 PCM，按 outputStreamId 路由
 */
interface TranslationModeHandler {
    val modeId: Int
    val inputStreams: List<String>
    val outputStreams: List<String>

    fun start(args: Map<String, Any?>)
    fun stop()
    val isWorking: Boolean

    /** 外部翻译服务回送的 PCM 注入点，由 TranslationFeature 路由到当前活动 handler */
    fun onTranslatedAudio(
        outputStreamId: String,
        pcm: ByteArray,
        format: AudioFormat,
        isFinal: Boolean,
    ): Boolean
}

abstract class BaseTranslationModeHandler(
    protected val btManager: JL_BluetoothManager,
    protected val bridge: TranslationAudioBridge,
) : TranslationModeHandler {

    @Volatile
    protected var working: Boolean = false

    override val isWorking: Boolean get() = working

    /** 把采集到的一帧 PCM 推给外部翻译服务 */
    protected fun pushFrame(
        streamId: String,
        pcm: ByteArray,
        format: AudioFormat = AudioFormat(),
        seq: Long = System.nanoTime(),
        isFinal: Boolean = false,
    ) {
        bridge.emitAudioFrame(modeId, streamId, pcm, format, seq, System.currentTimeMillis(), isFinal)
    }

    protected fun emitLog(content: String) = bridge.emitLog(modeId, content)
    protected fun emitError(code: Int, msg: String?) = bridge.emitError(modeId, code, msg)
}

/**
 * 与 SDK [com.jieli.bluetooth.bean.translation.TranslationMode] 完全一致的取值，
 * 方便直接拿插件 modeId 去构造 SDK 的 TranslationMode。
 */
object TranslationModeIds {
    const val MODE_IDLE = 0
    const val MODE_RECORD = 1
    const val MODE_RECORDING_TRANSLATION = 2
    const val MODE_CALL_TRANSLATION = 3
    const val MODE_AUDIO_TRANSLATION = 4
    const val MODE_FACE_TO_FACE_TRANSLATION = 5
    const val MODE_CALL_TRANSLATION_WITH_STEREO = 6
}
