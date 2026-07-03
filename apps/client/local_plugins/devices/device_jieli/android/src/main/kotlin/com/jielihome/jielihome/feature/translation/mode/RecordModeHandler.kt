package com.jielihome.jielihome.feature.translation.mode

import android.bluetooth.BluetoothDevice
import android.content.Context
import android.util.Log
import com.jieli.bluetooth.bean.translation.AudioData
import com.jieli.bluetooth.bean.translation.TranslationMode
import com.jieli.bluetooth.constant.Constants
import com.jieli.bluetooth.impl.JL_BluetoothManager
import com.jieli.bluetooth.impl.rcsp.translation.TranslationImpl
import com.jieli.bluetooth.interfaces.rcsp.callback.OnRcspActionCallback
import com.jieli.bluetooth.interfaces.rcsp.translation.TranslationCallback
import com.jielihome.jielihome.audio.PhoneMicCapture
import com.jielihome.jielihome.feature.translation.AudioFormat
import com.jielihome.jielihome.feature.translation.BaseTranslationModeHandler
import com.jielihome.jielihome.feature.translation.TranslationAudioBridge
import com.jielihome.jielihome.feature.translation.TranslationModeIds
import com.jielihome.jielihome.feature.translation.TranslationStreams
import com.jielihome.jielihome.feature.translation.runtime.NoOpAITranslationApi

/**
 * MODE_RECORD —— 单向录音翻译（mode=1）。
 *
 * # 与 JL_HomeSdkDemo 对齐
 * Demo 里 TranslationFragment 进入"录音"时会调 `TranslationImpl.enterMode(MODE_RECORD=1, ...)`，
 * 耳机端 RCSP 状态机随之从 MODE_IDLE(0) 切到 MODE_RECORD(0x01)，耳机可能播放提示音 / 切 LED 状态。
 * 之前本类仅启动手机麦、**未发 enterMode**，导致耳机侧始终停在 IDLE(0)，固件不认。
 *
 * 现在按 demo：
 *   1. 构造 TranslationMode(mode=1, OPUS/PCM, ch=1, sampleRate)
 *      + setRecordingStrategy(STRATEGY_CUSTOM_RECORDING=0)
 *   2. TranslationImpl.enterMode(mode, callback) 通知耳机进入 RECORD 模式
 *   3. STRATEGY_CUSTOM_RECORDING 语义 → APP 用手机麦采音（与 demo 一致）
 *   4. stop() 调 exitMode 让耳机回到 IDLE，避免状态机残留
 *
 * # 音频流向
 *   - 输入：手机麦 → PhoneMicCapture → pushFrame → 外部翻译服务
 *   - 输出：OUT_SPEAKER 由宿主自行播放（STRATEGY_CUSTOM_RECORDING 不走 RCSP 下发 TTS）
 *
 * # 与 DeviceRecordFeature 区分
 *   - 本类仍是 "手机麦 + 通知耳机进 RECORD 状态"，和 demo 对齐
 *   - DeviceRecordFeature 用 `MODE_CALL_TRANSLATION + STRATEGY_DEVICE_ALWAYS_RECORDING`
 *     直接从耳机麦抓 OPUS 上行帧，路径完全不同
 */
class RecordModeHandler(
    private val context: Context,
    btManager: JL_BluetoothManager,
    bridge: TranslationAudioBridge,
) : BaseTranslationModeHandler(btManager, bridge) {

    companion object {
        private const val TAG = "RecordModeHandler"
    }

    override val modeId = TranslationModeIds.MODE_RECORD
    override val inputStreams = listOf(TranslationStreams.IN_MIC)
    override val outputStreams = listOf(TranslationStreams.OUT_SPEAKER)

    private var mic: PhoneMicCapture? = null
    @Volatile private var translationImpl: TranslationImpl? = null
    @Volatile private var activeDevice: BluetoothDevice? = null

    private val translationCallback = object : TranslationCallback {
        override fun onModeChange(d: BluetoothDevice, m: TranslationMode) {
            Log.i(TAG, "[SDK<-DEV] onModeChange addr=${d.address} mode=${m.mode} type=${m.audioType} sr=${m.sampleRate} strategy=${m.recordingStrategy}")
        }

        override fun onReceiveAudioData(d: BluetoothDevice, data: AudioData) {
            // STRATEGY_CUSTOM_RECORDING 下耳机不上推音频；若固件仍推帧则忽略。
        }

        override fun onError(d: BluetoothDevice, code: Int, msg: String) {
            Log.e(TAG, "[SDK<-DEV] TranslationCallback.onError code=$code msg=$msg")
            emitError(code, msg)
        }
    }

    override fun start(args: Map<String, Any?>) {
        if (working) return
        val sampleRate = (args["sampleRate"] as? Int) ?: 16000
        val frameMs = (args["frameDurationMs"] as? Int) ?: 20

        // 1. 发 enterMode 让耳机进入 MODE_RECORD（0x01）状态，与 demo 对齐
        val device = btManager.connectedDevice
        if (device == null) {
            emitError(-200, "no connected device; cannot enter MODE_RECORD")
            return
        }
        val impl = TranslationImpl(btManager, NoOpAITranslationApi(), device)
        if (!impl.isInit) {
            runCatching { impl.destroy() }
            emitError(-201, "RCSP not init for ${device.address}")
            return
        }
        val sdkMode = TranslationMode(
            TranslationMode.MODE_RECORD,          // mode=1
            Constants.AUDIO_TYPE_PCM,             // RECORD 模式不需要 OPUS 编码，直接 PCM
            1,
            sampleRate,
        ).setRecordingStrategy(TranslationMode.STRATEGY_CUSTOM_RECORDING) // =0，APP 自己用手机麦采
        impl.addTranslationCallback(translationCallback)
        Log.i(TAG, "[APP->SDK] enterMode addr=${device.address} mode=${sdkMode.mode}(MODE_RECORD) type=${sdkMode.audioType} sr=${sdkMode.sampleRate} strategy=${sdkMode.recordingStrategy}(CUSTOM_RECORDING)")
        impl.enterMode(sdkMode, translationCallback)
        translationImpl = impl
        activeDevice = device

        // 2. 启动手机麦采集（STRATEGY_CUSTOM_RECORDING 语义）
        mic = PhoneMicCapture(
            context, sampleRate, frameMs,
            onFrame = { pcm -> pushFrame(TranslationStreams.IN_MIC, pcm, AudioFormat(sampleRate, 1, 16)) },
            onError = { code, msg -> emitError(code, msg) },
        )
        if (mic?.start() != true) {
            // 起麦失败：回滚耳机端模式，避免卡在 RECORD
            exitHeadsetMode()
            return
        }
        working = true
        emitLog("RecordMode start sampleRate=$sampleRate (headset in MODE_RECORD=1, phone mic active)")
    }

    override fun stop() {
        if (!working) return
        mic?.stop()
        mic = null
        exitHeadsetMode()
        working = false
        emitLog("RecordMode stop (headset back to MODE_IDLE=0)")
    }

    /** 让耳机 exitMode 回到 IDLE，并释放 TranslationImpl。幂等。 */
    private fun exitHeadsetMode() {
        val impl = translationImpl ?: return
        val addr = activeDevice?.address
        runCatching {
            Log.i(TAG, "[APP->SDK] exitMode addr=$addr mode=${TranslationMode.MODE_RECORD}")
            impl.exitMode(object : OnRcspActionCallback<Int> {
                override fun onSuccess(d: BluetoothDevice?, t: Int?) {
                    Log.i(TAG, "[APP->SDK] exitMode onSuccess addr=${d?.address} t=$t")
                }
                override fun onError(d: BluetoothDevice?, err: com.jieli.bluetooth.bean.base.BaseError?) {
                    Log.w(TAG, "[APP->SDK] exitMode onError addr=${d?.address} code=${err?.code} msg=${err?.message}")
                }
            })
        }
        runCatching { impl.removeTranslationCallback(translationCallback) }
        runCatching { impl.destroy() }
        translationImpl = null
        activeDevice = null
    }

    override fun onTranslatedAudio(
        outputStreamId: String,
        pcm: ByteArray,
        format: AudioFormat,
        isFinal: Boolean,
    ): Boolean {
        if (outputStreamId != TranslationStreams.OUT_SPEAKER) return false
        // RECORD 模式下耳机不参与回送；如果宿主想播给用户听，自己用 AudioTrack 播即可。
        emitLog("recv tts pcm=${pcm.size}B final=$isFinal (host-side playback)")
        return true
    }
}
