package com.jielihome.jielihome.feature.translation.runtime

import android.bluetooth.BluetoothDevice
import android.util.Log
import com.jieli.bluetooth.bean.translation.AudioData
import com.jieli.bluetooth.bean.translation.TranslationMode
import com.jieli.bluetooth.constant.Constants
import com.jieli.bluetooth.impl.JL_BluetoothManager
import com.jieli.bluetooth.impl.rcsp.translation.TranslationImpl
import com.jieli.bluetooth.interfaces.rcsp.callback.OnRcspActionCallback
import com.jieli.bluetooth.interfaces.rcsp.translation.TranslationCallback
import java.io.File

/**
 * RCSP 翻译模式运行时（call translation 路径专用）。
 *
 * # 角色
 * 把"进入/退出 SDK 翻译模式"的 RCSP 状态机生命周期，跟「上下行音频接力」绑在一起。
 * 真正的音频路由由 [JieliAITranslationBridge] 这个 [com.jieli.bluetooth.interfaces.rcsp.translation.IAITranslationApi]
 * 实现负责（见它头注释）。
 *
 * # 与旧实现的区别
 * 之前的 runtime 大约 500 行：自己用 [TranslationCallback.onReceiveAudioData] 拿上行 OPUS、
 * 自己 OPUS 编码 TTS、自己维护 `WriteScheduler` 串行队列调 [TranslationImpl.writeAudioData]。
 * 实测耳机端解码器频繁 reset 导致杂音 / 断续。
 *
 * 现在按官方 demo `AITranslationImpl` 的标准做法：
 *   1. 构造 [TranslationImpl] 时传入真正的 [JieliAITranslationBridge]，SDK 通过它把上行
 *      OPUS 推给我们解码；
 *   2. 下行 TTS PCM 累积成段后通过 [AITranslationCallback.onTranslateResult] 交给 SDK，
 *      由 SDK 内部完成 cmd=52 切包 / 写时序 / 缓冲水位（[TranslationImpl.PushDataWrapper]）。
 *
 * # 上下行 source 字段语义
 *   - 通话翻译给「对端听」  → AudioData.source = SOURCE_E_SCO_UP_LINK
 *   - 通话翻译给「本机听」  → AudioData.source = SOURCE_E_SCO_DOWN_LINK
 *   - 录音/音视频/面对面    → AudioData.source = SOURCE_PHONE_MIC（SDK 按 mode 自分发）
 */
class RcspTranslationRuntime(
    private val btManager: JL_BluetoothManager,
    private val device: BluetoothDevice,
    private val mode: TranslationMode,
    private val tempDir: File,
    /** 解码（或直传 PCM）后的音频上行；source 为 SDK 原值 */
    private val onPcm: (source: Int, pcm: ByteArray) -> Unit,
    private val onError: (code: Int, msg: String?) -> Unit,
    /** OPUS 解码 packetSize；mono call=200，stereo=80 */
    private val opusPacketSize: Int = if (mode.channel == 2) 80 else 200,
) {

    companion object {
        private const val TAG = "RcspTranslationRuntime"
    }

    /** SDK 的 AI hook 实现：上行解码、下行 TTS 接力都在这里。 */
    private val bridge = JieliAITranslationBridge(
        mode = mode,
        tempDir = tempDir,
        onPcm = onPcm,
        onError = onError,
        opusPacketSize = opusPacketSize,
    )

    private val translationImpl = TranslationImpl(btManager, bridge, device)
    private val isPcmMode = mode.audioType == Constants.AUDIO_TYPE_PCM

    /**
     * 仅订阅 mode 变化事件用于日志 / 异常上报；不在这里消费音频
     * （音频走 [bridge] 的 `IAITranslationApi.writeAudio`，避免双路重复消费）。
     */
    private val translationCallback = object : TranslationCallback {
        override fun onModeChange(d: BluetoothDevice, m: TranslationMode) {
            Log.i(
                TAG,
                "[SDK<-DEV] onModeChange addr=${d.address} mode=${m.mode} type=${m.audioType} " +
                        "sr=${m.sampleRate} ch=${m.channel} strategy=${m.recordingStrategy}"
            )
            if (m.mode == TranslationMode.MODE_IDLE && mode.mode != TranslationMode.MODE_IDLE) {
                onError(-1, "headset exited mode=${mode.mode} → MODE_IDLE")
            }
        }

        override fun onReceiveAudioData(d: BluetoothDevice, data: AudioData) {
            // 音频走 bridge.writeAudio；这里不消费，避免与 bridge 双路重复解码。
        }

        override fun onError(d: BluetoothDevice, code: Int, msg: String) {
            Log.e(TAG, "[SDK<-DEV] TranslationCallback.onError code=$code msg=$msg")
            this@RcspTranslationRuntime.onError(code, msg)
        }
    }

    /** 启动前置校验 + 进入翻译模式。 */
    fun start(): Result<Unit> {
        if (!translationImpl.isInit) {
            return Result.failure(IllegalStateException("RCSP not init for ${device.address}"))
        }
        if (!translationImpl.isSupportTranslation) {
            return Result.failure(IllegalStateException("device does not support translation"))
        }
        if (mode.mode == TranslationMode.MODE_CALL_TRANSLATION_WITH_STEREO &&
            !translationImpl.isSupportCallTranslationWithStereo
        ) {
            return Result.failure(IllegalStateException("device does not support stereo call translation"))
        }
        if (!tempDir.exists()) tempDir.mkdirs()

        translationImpl.addTranslationCallback(translationCallback)
        Log.i(
            TAG,
            "[APP->SDK] enterMode addr=${device.address} mode=${mode.mode} type=${mode.audioType} " +
                    "sr=${mode.sampleRate} ch=${mode.channel} strategy=${mode.recordingStrategy} " +
                    "(SDK will drive bridge.startTranslating)"
        )
        translationImpl.enterMode(mode, translationCallback)
        return Result.success(Unit)
    }

    /**
     * 把外部翻译服务回送的 PCM 接力给 SDK。
     *
     * 行为完全委托给 [JieliAITranslationBridge.feedTtsPcm]：
     *  - PCM 模式：每次调用作为一段 [AudioData] 立即交付给 SDK；
     *  - OPUS 模式：累积，`isFinal=true` 时整段编码 → `onTranslateResult` 交给 SDK。
     *
     * 调用方契约：**必须**在 utterance 末尾调一次 `isFinal=true`，否则音频会一直累积
     * 到 2MB 兜底上限才出。
     */
    fun feedTtsPcm(outputStreamId: String, pcm: ByteArray, isFinal: Boolean): Boolean =
        bridge.feedTtsPcm(outputStreamId, pcm, isFinal)

    fun stop() {
        runCatching {
            Log.i(TAG, "[APP->SDK] exitMode addr=${device.address} mode=${mode.mode}")
            translationImpl.exitMode(object : OnRcspActionCallback<Int> {
                override fun onSuccess(d: BluetoothDevice?, t: Int?) {
                    Log.i(TAG, "[APP->SDK] exitMode onSuccess addr=${d?.address} t=$t")
                }
                override fun onError(d: BluetoothDevice?, err: com.jieli.bluetooth.bean.base.BaseError?) {
                    Log.w(TAG, "[APP->SDK] exitMode onError addr=${d?.address} code=${err?.code} msg=${err?.message}")
                }
            })
        }
        runCatching { translationImpl.removeTranslationCallback(translationCallback) }
        // bridge 由 SDK 在 exitMode 后通过 stopTranslating 自动 release decoders；
        // 这里不重复调，避免双重 stop。
        runCatching { translationImpl.destroy() }
    }
}
