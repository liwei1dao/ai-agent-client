package com.jielihome.jielihome.feature.translation

import android.content.Context
import com.jieli.bluetooth.impl.JL_BluetoothManager
import com.jielihome.jielihome.feature.ConnectFeature
import com.jielihome.jielihome.feature.translation.mode.AudioTranslationModeHandler
import com.jielihome.jielihome.feature.translation.mode.CallTranslationModeHandler
import com.jielihome.jielihome.feature.translation.mode.FaceToFaceTranslationModeHandler
import com.jielihome.jielihome.feature.translation.mode.RecordModeHandler
import com.jielihome.jielihome.feature.translation.mode.RecordingTranslationModeHandler
import com.jielihome.jielihome.feature.translation.mode.StereoCallTranslationModeHandler

/**
 * 翻译特性入口。
 *
 * # TTS PCM 回灌的两条路径
 * 宿主把外部翻译服务回送的 PCM 注入回插件时，**两条路径同时存在、宿主只需选一条**：
 *
 *   1) Dart / 远端进程 → MethodChannel `feedTranslatedAudio` → MethodRouter →
 *      `TranslationFeature.feedTranslatedAudio` → 当前 [TranslationModeHandler.onTranslatedAudio]
 *      场景：Flutter UI 调用，或宿主原生代码使用通用入口（不区分桥实现时）。
 *
 *   2) 自定义 native bridge → `TranslationAudioBridge.feedTranslatedAudio` →
 *      （桥内部决定如何下发；默认实现 [EventChannelAudioBridge] 通过 injector 转回 1）。
 *      场景：宿主用 [setBridge] 替换桥，希望把音频生命周期完全留在 native 层管理。
 *
 * 推荐：除非有性能/隔离强需求，**统一走路径 1**（更简单、字幕和音频走同一条命令通道）。
 *
 * # 立体声通话翻译
 * `MODE_CALL_TRANSLATION` 永远是双流单声道；`MODE_CALL_TRANSLATION_WITH_STEREO`
 * 永远走立体声软件分声道方案。是否切到后者由调用方自行判断，可先调
 * [isSupportCallTranslationWithStereo] 探测设备能力。
 */
class TranslationFeature(
    private val context: Context,
    private val btManager: JL_BluetoothManager,
    private val connectFeature: ConnectFeature,
) {
    @Volatile
    private var bridge: TranslationAudioBridge? = null

    private var handlers: Map<Int, TranslationModeHandler> = emptyMap()

    @Volatile
    private var current: TranslationModeHandler? = null

    /** 由 JieliHomeServer 在 init 时调一次；后续宿主可调 [setBridge] 替换 */
    fun setBridge(bridge: TranslationAudioBridge) {
        this.bridge = bridge
        // 重建 handlers，把新桥 + 上下文注入下去
        handlers = mapOf(
            TranslationModeIds.MODE_RECORD to RecordModeHandler(context, btManager, bridge),
            TranslationModeIds.MODE_RECORDING_TRANSLATION to RecordingTranslationModeHandler(context, btManager, bridge),
            TranslationModeIds.MODE_CALL_TRANSLATION to CallTranslationModeHandler(context, btManager, connectFeature, bridge),
            TranslationModeIds.MODE_CALL_TRANSLATION_WITH_STEREO to StereoCallTranslationModeHandler(context, btManager, connectFeature, bridge),
            TranslationModeIds.MODE_AUDIO_TRANSLATION to AudioTranslationModeHandler(btManager, bridge),
            TranslationModeIds.MODE_FACE_TO_FACE_TRANSLATION to FaceToFaceTranslationModeHandler(context, btManager, bridge),
        )
    }

    fun start(modeId: Int, args: Map<String, Any?>): Result<Unit> {
        // 与官方 demo (TranslationViewModel.enterMode) 对齐：MODE_CALL_TRANSLATION
        // + OPUS + 设备支持立体声方案时，自动升级到 MODE_CALL_TRANSLATION_WITH_STEREO
        // (channel=2)。很多固件版本下 mono CALL_TRANSLATION 通路实际上不出帧，
        // 真正出数据的是立体声方案——上下行 mix 成一路立体声 PCM 上推。
        val effectiveModeId = if (
            modeId == TranslationModeIds.MODE_CALL_TRANSLATION &&
            (args["audioType"] == null ||
                args["audioType"] == com.jieli.bluetooth.constant.Constants.AUDIO_TYPE_OPUS ||
                (args["audioType"] as? String)?.lowercase() == "opus") &&
            isSupportCallTranslationWithStereo(args["address"] as? String)
        ) {
            android.util.Log.d(
                "TranslationFeature",
                "MODE_CALL_TRANSLATION + OPUS + stereo-supported → upgrade to MODE_CALL_TRANSLATION_WITH_STEREO",
            )
            TranslationModeIds.MODE_CALL_TRANSLATION_WITH_STEREO
        } else modeId

        val handler = handlers[effectiveModeId]
            ?: return Result.failure(IllegalArgumentException("unknown modeId=$effectiveModeId"))
        current?.takeIf { it.isWorking }?.stop()
        handler.start(args)
        current = handler
        return Result.success(Unit)
    }

    fun stop() {
        current?.takeIf { it.isWorking }?.stop()
        current = null
    }

    fun isWorking(): Boolean = current?.isWorking == true
    fun currentModeId(): Int? = current?.modeId
    fun currentInputStreams(): List<String> = current?.inputStreams ?: emptyList()
    fun currentOutputStreams(): List<String> = current?.outputStreams ?: emptyList()

    /**
     * 翻译服务回送 TTS PCM 的统一入口。
     * 路由到当前活动 ModeHandler 的 onTranslatedAudio。
     */
    fun feedTranslatedAudio(
        outputStreamId: String,
        pcm: ByteArray,
        format: AudioFormat,
        isFinal: Boolean,
    ): Boolean {
        val h = current ?: return false
        if (!h.isWorking) return false
        if (outputStreamId !in h.outputStreams) return false
        return h.onTranslatedAudio(outputStreamId, pcm, format, isFinal)
    }

    /** 透传文本结果（字幕）；requestId 由调用方贯穿同一段翻译，便于聚合 */
    fun feedTranslationResult(
        srcLang: String?, srcText: String?,
        destLang: String?, destText: String?,
        requestId: String? = null,
    ) {
        val mid = current?.modeId ?: return
        bridge?.emitTranslationResult(mid, srcLang, srcText, destLang, destText, requestId)
    }

    /**
     * 探测当前已连耳机是否支持立体声通话翻译方案。
     * 内部根据 SDK [com.jieli.bluetooth.impl.rcsp.translation.TranslationImpl.isSupportCallTranslationWithStereo]
     * 判断；若设备未连或未握手 RCSP 则返回 false。
     */
    fun isSupportCallTranslationWithStereo(connectedDeviceAddress: String?): Boolean {
        val device = connectedDeviceAddress?.let {
            com.jieli.bluetooth.utils.BluetoothUtil.getRemoteDevice(it)
        } ?: btManager.connectedDevice ?: return false
        val tmp = com.jieli.bluetooth.impl.rcsp.translation.TranslationImpl(
            btManager,
            com.jielihome.jielihome.feature.translation.runtime.NoOpAITranslationApi(),
            device,
        )
        return runCatching { tmp.isSupportCallTranslationWithStereo }.getOrDefault(false)
            .also { runCatching { tmp.destroy() } }
    }

    /**
     * 把外部音频文件解码后的 PCM 灌入「音视频翻译」模式（仅在该模式生效）。
     */
    fun feedAudioFilePcm(pcm: ByteArray, sampleRate: Int = 16000): Boolean {
        val h = current as? com.jielihome.jielihome.feature.translation.mode.AudioTranslationModeHandler
            ?: return false
        h.feedFilePcm(pcm, sampleRate)
        return true
    }
}
