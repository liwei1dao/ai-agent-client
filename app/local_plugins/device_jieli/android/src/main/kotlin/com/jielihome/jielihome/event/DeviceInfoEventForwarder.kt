package com.jielihome.jielihome.event

import android.bluetooth.BluetoothDevice
import com.jieli.bluetooth.bean.base.VoiceMode
import com.jieli.bluetooth.bean.device.status.BatteryInfo
import com.jieli.bluetooth.bean.device.voice.VoiceFunc
import com.jieli.bluetooth.impl.JL_BluetoothManager
import com.jieli.bluetooth.interfaces.rcsp.callback.OnRcspEventListener
import com.jielihome.jielihome.bridge.EventDispatcher

/**
 * 设备信息类事件（设备主动推送）：电量、来电状态、语音模式/功能、双连状态。
 *
 * 实现思路：注册一个 OnRcspEventListener 实例，按主题分配到不同 forwarder。
 * 这里只负责「设备级状态」，多媒体放 MediaEventForwarder，私有协议放 CustomEventForwarder。
 *
 * 多个 forwarder 各注册一个独立 listener，SDK 会全部派发，互不干扰。
 */
class DeviceInfoEventForwarder(
    private val btManager: JL_BluetoothManager,
    private val dispatcher: EventDispatcher,
) {
    private val listener = object : OnRcspEventListener() {

        override fun onBatteryChange(device: BluetoothDevice?, info: BatteryInfo?) {
            dispatcher.send(
                mapOf(
                    "type" to "battery",
                    "address" to device?.address,
                    "level" to info?.battery
                )
            )
        }

        override fun onPhoneCallStatusChange(device: BluetoothDevice?, status: Int) {
            dispatcher.send(
                mapOf(
                    "type" to "phoneCallStatus",
                    "address" to device?.address,
                    "status" to status
                )
            )
        }

        override fun onCurrentVoiceMode(device: BluetoothDevice?, mode: VoiceMode?) {
            dispatcher.send(
                mapOf(
                    "type" to "voiceMode",
                    "address" to device?.address,
                    "modeId" to mode?.mode
                )
            )
        }

        override fun onVoiceFunctionChange(device: BluetoothDevice?, func: VoiceFunc?) {
            dispatcher.send(
                mapOf(
                    "type" to "voiceFunction",
                    "address" to device?.address,
                    "function" to func?.toString()
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
