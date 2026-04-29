package com.jielihome.jielihome.event

import android.bluetooth.BluetoothDevice
import com.jieli.bluetooth.bean.device.eq.EqInfo
import com.jieli.bluetooth.bean.device.music.MusicNameInfo
import com.jieli.bluetooth.bean.device.music.MusicStatusInfo
import com.jieli.bluetooth.bean.device.music.PlayModeInfo
import com.jieli.bluetooth.bean.device.voice.VolumeInfo
import com.jieli.bluetooth.impl.JL_BluetoothManager
import com.jieli.bluetooth.interfaces.rcsp.callback.OnRcspEventListener
import com.jielihome.jielihome.bridge.EventDispatcher

/**
 * 多媒体事件：音乐名/状态/播放模式、EQ、音量。
 */
class MediaEventForwarder(
    private val btManager: JL_BluetoothManager,
    private val dispatcher: EventDispatcher,
) {
    private val listener = object : OnRcspEventListener() {

        override fun onVolumeChange(device: BluetoothDevice?, info: VolumeInfo?) {
            dispatcher.send(
                mapOf(
                    "type" to "volume",
                    "address" to device?.address,
                    "current" to info?.volume,
                    "max" to info?.maxVol
                )
            )
        }

        override fun onEqChange(device: BluetoothDevice?, info: EqInfo?) {
            dispatcher.send(
                mapOf("type" to "eq", "address" to device?.address, "info" to info?.toString())
            )
        }

        override fun onMusicNameChange(device: BluetoothDevice?, info: MusicNameInfo?) {
            dispatcher.send(
                mapOf(
                    "type" to "musicName",
                    "address" to device?.address,
                    "name" to info?.name
                )
            )
        }

        override fun onMusicStatusChange(device: BluetoothDevice?, info: MusicStatusInfo?) {
            dispatcher.send(
                mapOf(
                    "type" to "musicStatus",
                    "address" to device?.address,
                    "playing" to info?.isPlay,
                    "currentTime" to info?.currentTime,
                    "totalTime" to info?.totalTime
                )
            )
        }

        override fun onPlayModeChange(device: BluetoothDevice?, info: PlayModeInfo?) {
            dispatcher.send(
                mapOf(
                    "type" to "playMode",
                    "address" to device?.address,
                    "mode" to info?.playMode
                )
            )
        }
    }

    fun attach() {
        btManager.registerOnRcspEventListener(listener)
    }

    fun detach() {
        btManager.unregisterOnRcspEventListener(listener)
    }
}
