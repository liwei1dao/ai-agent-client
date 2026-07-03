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
 * MODE_RECORDING_TRANSLATION —— 流式录音翻译（mode=2）。等同于 RecordMode 的实时版，
 * 差别只在语义：调用方实现实时 STT/翻译流水线、不缓存整段录音再发。
 *
 * # 与 JL_HomeSdkDemo 对齐
 * Demo 会调 `TranslationImpl.enterMode(MODE_RECORDING_TRANSLATION=2, ...)` 让耳机进入状态机。
 * 之前本类仅启动手机麦、**未发 enterMode**，耳机侧始终停在 MODE_IDLE(0)，固件不认。
 *
 * 现在按 demo：
 *   1. 构造 TranslationMode(mode=2, PCM, ch=1, sampleRate)
 *      + setRecordingStrategy(STRATEGY_CUSTOM_RECORDING=0)
 *   2. TranslationImpl.enterMode 通知耳机进入录音翻译模式
 *   3. APP 用手机麦采音并 pushFrame（与 demo 一致）
 *   4. stop() 调 exitMode 让耳机回到 IDLE
 */
class RecordingTranslationModeHandler(
    private val context: Context,
    btManager: JL_BluetoothManager,
    bridge: TranslationAudioBridge,
) : BaseTranslationModeHandler(btManager, bridge) {

    companion object {
        private const val TAG = "RecTransModeHandler"
    }

    override val modeId = TranslationModeIds.MODE_RECORDING_TRANSLATION
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

        // 1. 发 enterMode 让耳机进入 MODE_RECORDING_TRANSLATION（0x02）状态，与 demo 对齐
        val device = btManager.connectedDevice
        if (device == null) {
            emitError(-200, "no connected device; cannot enter MODE_RECORDING_TRANSLATION")
            return
        }
        val impl = TranslationImpl(btManager, NoOpAITranslationApi(), device)
        if (!impl.isInit) {
            runCatching { impl.destroy() }
            emitError(-201, "RCSP not init for ${device.address}")
            return
        }
        val sdkMode = TranslationMode(
            TranslationMode.MODE_RECORDING_TRANSLATION,  // mode=2
            Constants.AUDIO_TYPE_PCM,
            1,
            sampleRate,
        ).setRecordingStrategy(TranslationMode.STRATEGY_CUSTOM_RECORDING)
        impl.addTranslationCallback(translationCallback)
        Log.i(TAG, "[APP->SDK] enterMode addr=${device.address} mode=${sdkMode.mode}(MODE_RECORDING_TRANSLATION) type=${sdkMode.audioType} sr=${sdkMode.sampleRate} strategy=${sdkMode.recordingStrategy}(CUSTOM_RECORDING)")
        impl.enterMode(sdkMode, translationCallback)
        translationImpl = impl
        activeDevice = device

        // 2. 启动手机麦采集
        mic = PhoneMicCapture(
            context, sampleRate,
            onFrame = { pcm -> pushFrame(TranslationStreams.IN_MIC, pcm, AudioFormat(sampleRate, 1, 16)) },
            onError = { code, msg -> emitError(code, msg) },
        )
        if (mic?.start() != true) {
            exitHeadsetMode()
            return
        }
        working = true
        emitLog("RecordingTranslation start sampleRate=$sampleRate (headset in MODE_RECORDING_TRANSLATION=2)")
    }

    override fun stop() {
        if (!working) return
        mic?.stop()
        mic = null
        exitHeadsetMode()
        working = false
        emitLog("RecordingTranslation stop (headset back to MODE_IDLE=0)")
    }

    /** 让耳机 exitMode 回到 IDLE，并释放 TranslationImpl。幂等。 */
    private fun exitHeadsetMode() {
        val impl = translationImpl ?: return
        val addr = activeDevice?.address
        runCatching {
            Log.i(TAG, "[APP->SDK] exitMode addr=$addr mode=${TranslationMode.MODE_RECORDING_TRANSLATION}")
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
        emitLog("recv tts ${pcm.size}B final=$isFinal")
        return true
    }
}
