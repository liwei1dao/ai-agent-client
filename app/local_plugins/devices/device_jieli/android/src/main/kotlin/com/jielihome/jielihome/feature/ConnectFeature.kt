package com.jielihome.jielihome.feature

import android.bluetooth.BluetoothDevice
import com.jieli.bluetooth.constant.BluetoothConstant
import com.jieli.bluetooth.constant.JL_DeviceType
import com.jieli.bluetooth.impl.JL_BluetoothManager
import com.jieli.bluetooth.utils.BluetoothUtil

/**
 * 连接功能。
 *
 * # 协议选择策略（[resolveTarget]）
 * 默认**走 SPP（经典蓝牙 RFCOMM）**——只要拿得到 EDR 地址、且不是手表设备：
 *   - 有 [edrAddress] 且 [deviceType] != WATCH：
 *       * [connectWay] 显式指定 `GATT_OVER_BR_EDR(2)`：用 GATT_OVER_BR_EDR
 *       * 其余情况（包括 SDK 默认 0 / 上层未指定 / 扫描解析回 SPP）：用 **SPP(1)**
 *   - 否则（无 edrAddr 或 WATCH 设备）：**fallback BLE(0)**
 *
 * 这个策略把"默认 SPP"作为成年男耳机/带 EDR 设备的首选——这类设备本身设计走经典
 * 蓝牙 + RCSP over SPP，BLE-only 通路在 OPUS 高速下行场景下吞吐受限。手表 / 仅 BLE
 * 的设备会自动 fallback BLE，不影响其工作。
 */
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

        // 手表强制 BLE：JL Watch 系列只暴露 GATT，没有 SPP profile
        if (deviceType == JL_DeviceType.JL_DEVICE_TYPE_WATCH) {
            return ble to BluetoothConstant.PROTOCOL_TYPE_BLE
        }

        // 默认走 SPP；调用方显式要求 GATT_OVER_BR_EDR 时尊重之
        if (!edrAddress.isNullOrEmpty()) {
            val protocol = if (connectWay == BluetoothConstant.PROTOCOL_TYPE_GATT_OVER_BR_EDR) {
                BluetoothConstant.PROTOCOL_TYPE_GATT_OVER_BR_EDR
            } else {
                BluetoothConstant.PROTOCOL_TYPE_SPP
            }
            BluetoothUtil.getRemoteDevice(edrAddress)?.let { return it to protocol }
        }

        // 没有 EDR 地址，回退 BLE
        return ble to BluetoothConstant.PROTOCOL_TYPE_BLE
    }
}
