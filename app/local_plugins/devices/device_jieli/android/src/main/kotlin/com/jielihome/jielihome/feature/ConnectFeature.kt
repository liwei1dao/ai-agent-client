package com.jielihome.jielihome.feature

import android.bluetooth.BluetoothDevice
import com.jieli.bluetooth.constant.BluetoothConstant
import com.jieli.bluetooth.constant.JL_DeviceType
import com.jieli.bluetooth.impl.JL_BluetoothManager
import com.jieli.bluetooth.utils.BluetoothUtil

class ConnectFeature(private val btManager: JL_BluetoothManager) {

    fun connect(
        bleAddress: String,
        edrAddress: String?,
        deviceType: Int,
        connectWay: Int,
    ): Result<Unit> {
        val target = resolveTarget(bleAddress, edrAddress, deviceType, connectWay)
            ?: return Result.failure(IllegalStateException("remote device not found"))
        btManager.connect(target.first, target.second)
        return Result.success(Unit)
    }

    fun disconnect(address: String): Result<Unit> {
        val device = BluetoothUtil.getRemoteDevice(address)
            ?: return Result.failure(IllegalStateException("remote device not found"))
        btManager.disconnect(device)
        return Result.success(Unit)
    }

    fun isConnected(address: String): Boolean {
        val device = BluetoothUtil.getRemoteDevice(address) ?: return false
        return btManager.isConnectedBtDevice(device)
    }

    fun connectedDevice(): BluetoothDevice? = btManager.connectedDevice

    fun deviceByAddress(address: String): BluetoothDevice? =
        BluetoothUtil.getRemoteDevice(address)

    private fun resolveTarget(
        bleAddress: String,
        edrAddress: String?,
        deviceType: Int,
        connectWay: Int,
    ): Pair<BluetoothDevice, Int>? {
        val ble = BluetoothUtil.getRemoteDevice(bleAddress) ?: return null
        if (deviceType != JL_DeviceType.JL_DEVICE_TYPE_WATCH &&
            !edrAddress.isNullOrEmpty() &&
            (connectWay == BluetoothConstant.PROTOCOL_TYPE_SPP ||
                connectWay == BluetoothConstant.PROTOCOL_TYPE_GATT_OVER_BR_EDR)
        ) {
            BluetoothUtil.getRemoteDevice(edrAddress)?.let { return it to connectWay }
        }
        return ble to BluetoothConstant.PROTOCOL_TYPE_BLE
    }
}
