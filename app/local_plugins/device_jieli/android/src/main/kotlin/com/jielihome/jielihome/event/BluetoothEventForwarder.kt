package com.jielihome.jielihome.event

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import com.jieli.bluetooth.bean.BleScanMessage
import com.jieli.bluetooth.impl.JL_BluetoothManager
import com.jieli.bluetooth.interfaces.bluetooth.BluetoothCallbackImpl
import com.jieli.bluetooth.interfaces.rcsp.callback.OnRcspCallback
import com.jielihome.jielihome.bridge.EventDispatcher

/**
 * 蓝牙基础事件：适配器开关、扫描状态、设备发现、配对、RCSP init、连接状态。
 * 与设备「业务数据」（电量、音乐等）解耦。
 */
class BluetoothEventForwarder(
    private val btManager: JL_BluetoothManager,
    private val dispatcher: EventDispatcher,
) {
    private val btCallback = object : BluetoothCallbackImpl() {
        override fun onAdapterStatus(bEnabled: Boolean, bHasBle: Boolean) {
            dispatcher.send(
                mapOf("type" to "adapterStatus", "enabled" to bEnabled, "hasBle" to bHasBle)
            )
        }

        override fun onDiscoveryStatus(bBle: Boolean, bStart: Boolean) {
            dispatcher.send(
                mapOf("type" to "scanStatus", "ble" to bBle, "started" to bStart)
            )
        }

        @SuppressLint("MissingPermission")
        override fun onDiscovery(device: BluetoothDevice?, msg: BleScanMessage?) {
            if (device == null || msg == null) return
            val name = try { device.name } catch (_: SecurityException) { null } ?: return
            if (name.isEmpty()) return
            dispatcher.send(
                mapOf(
                    "type" to "deviceFound",
                    "name" to name,
                    "address" to device.address,
                    "edrAddr" to msg.edrAddr,
                    "deviceType" to msg.deviceType,
                    "connectWay" to msg.connectWay,
                    "rssi" to msg.rssi
                )
            )
        }

        override fun onBondStatus(device: BluetoothDevice?, status: Int) {
            if (device == null) return
            dispatcher.send(
                mapOf("type" to "bondStatus", "address" to device.address, "status" to status)
            )
        }
    }

    private val rcspCallback = object : OnRcspCallback() {
        override fun onRcspInit(device: BluetoothDevice?, code: Int) {
            if (device == null) return
            dispatcher.send(
                mapOf("type" to "rcspInit", "address" to device.address, "code" to code)
            )
            if (code != 0) btManager.disconnect(device)
        }

        override fun onConnectStateChange(device: BluetoothDevice?, status: Int) {
            if (device == null) return
            dispatcher.send(
                mapOf("type" to "connectionState", "address" to device.address, "state" to status)
            )
        }
    }

    fun attach() {
        btManager.addEventListener(btCallback)
        btManager.registerOnRcspCallback(rcspCallback)
    }

    fun detach() {
        btManager.removeEventListener(btCallback)
        btManager.unregisterOnRcspCallback(rcspCallback)
    }
}
