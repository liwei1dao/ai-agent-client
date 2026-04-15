package com.aiagent.plugin_interface

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.util.Log

/**
 * AudioOutputManager — 全局音频输出路由管理
 *
 * 支持三种模式：
 * - earpiece: 强制听筒输出
 * - speaker:  强制扬声器输出
 * - auto:     有耳机时走系统路由，无耳机时走扬声器
 *
 * 提供两套应用策略：
 * - applyMode():           用于非 WebRTC 音频（MediaPlayer/AudioTrack），
 *                          Android 12+ 使用 setCommunicationDevice()
 * - applyModeForWebRtc():  用于 WebRTC 场景，只用 setSpeakerphoneOn()，
 *                          避免 setCommunicationDevice() 触发设备变更回调
 *                          导致 JavaAudioDeviceModule 重新初始化 AudioRecord
 */
object AudioOutputManager {

    private const val TAG = "AudioOutputManager"

    enum class Mode { EARPIECE, SPEAKER, AUTO }

    @Volatile
    var currentMode: Mode = Mode.AUTO
        private set

    private var audioManager: AudioManager? = null

    fun init(context: Context) {
        audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    }

    /**
     * 设置音频输出模式并立即应用（非 WebRTC）
     */
    fun setMode(mode: Mode) {
        currentMode = mode
        Log.d(TAG, "setMode: $mode")
        applyMode()
    }

    /**
     * 应用音频路由 — 用于非 WebRTC 音频（MediaPlayer / AudioTrack）
     *
     * Android 12+ 使用 setCommunicationDevice() 精确指定设备，
     * 低版本使用 setSpeakerphoneOn()。
     */
    fun applyMode() {
        val am = audioManager ?: return
        am.mode = AudioManager.MODE_IN_COMMUNICATION

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            applyWithCommunicationDevice(am)
        } else {
            applyWithSpeakerphone(am)
        }
    }

    /**
     * 应用音频路由 — 专用于 WebRTC 场景
     *
     * WebRTC 的 JavaAudioDeviceModule 内部管理音频设备。
     * setCommunicationDevice() 会触发系统 AudioDeviceCallback，
     * 导致 JavaAudioDeviceModule 重新初始化 AudioRecord，录音中断。
     *
     * 因此 WebRTC 场景下只使用 setSpeakerphoneOn()，
     * 它在 MODE_IN_COMMUNICATION 下仍然有效（WebRTC 官方示例也用此方式），
     * 且不会触发设备变更回调。
     */
    @Suppress("DEPRECATION")
    fun applyModeForWebRtc() {
        val am = audioManager ?: return
        // 不要设置 am.mode，WebRTC 自己管理 AudioManager mode
        when (currentMode) {
            Mode.EARPIECE -> {
                am.isSpeakerphoneOn = false
                Log.d(TAG, "WebRTC: earpiece (speakerphoneOn=false)")
            }
            Mode.SPEAKER -> {
                am.isSpeakerphoneOn = true
                Log.d(TAG, "WebRTC: speaker (speakerphoneOn=true)")
            }
            Mode.AUTO -> {
                val headset = isHeadsetConnected(am)
                am.isSpeakerphoneOn = !headset
                Log.d(TAG, "WebRTC: auto → headset=$headset speakerphoneOn=${!headset}")
            }
        }
    }

    // ── 非 WebRTC 实现 ──

    @Suppress("NewApi")
    private fun applyWithCommunicationDevice(am: AudioManager) {
        val devices = am.availableCommunicationDevices

        when (currentMode) {
            Mode.EARPIECE -> {
                val earpiece = devices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE }
                if (earpiece != null) {
                    val ok = am.setCommunicationDevice(earpiece)
                    Log.d(TAG, "setCommunicationDevice(earpiece): $ok")
                } else {
                    Log.w(TAG, "No earpiece device found")
                }
            }
            Mode.SPEAKER -> {
                val speaker = devices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
                if (speaker != null) {
                    val ok = am.setCommunicationDevice(speaker)
                    Log.d(TAG, "setCommunicationDevice(speaker): $ok")
                } else {
                    am.clearCommunicationDevice()
                    @Suppress("DEPRECATION")
                    am.isSpeakerphoneOn = true
                    Log.w(TAG, "No speaker device, fallback speakerphoneOn")
                }
            }
            Mode.AUTO -> {
                if (isHeadsetConnected(am)) {
                    am.clearCommunicationDevice()
                    Log.d(TAG, "clearCommunicationDevice: headset detected")
                } else {
                    val speaker = devices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
                    if (speaker != null) {
                        val ok = am.setCommunicationDevice(speaker)
                        Log.d(TAG, "setCommunicationDevice(speaker) [auto]: $ok")
                    } else {
                        am.clearCommunicationDevice()
                        @Suppress("DEPRECATION")
                        am.isSpeakerphoneOn = true
                        Log.d(TAG, "auto → fallback speakerphoneOn")
                    }
                }
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun applyWithSpeakerphone(am: AudioManager) {
        when (currentMode) {
            Mode.EARPIECE -> {
                am.isSpeakerphoneOn = false
                Log.d(TAG, "Applied (legacy): earpiece")
            }
            Mode.SPEAKER -> {
                am.isSpeakerphoneOn = true
                Log.d(TAG, "Applied (legacy): speaker")
            }
            Mode.AUTO -> {
                val headset = isHeadsetConnected(am)
                am.isSpeakerphoneOn = !headset
                Log.d(TAG, "Applied (legacy): auto → headset=$headset")
            }
        }
    }

    private fun isHeadsetConnected(am: AudioManager): Boolean {
        val devices = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        return devices.any { device ->
            device.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
            device.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
            device.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
            device.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
            device.type == AudioDeviceInfo.TYPE_USB_HEADSET
        }
    }
}
