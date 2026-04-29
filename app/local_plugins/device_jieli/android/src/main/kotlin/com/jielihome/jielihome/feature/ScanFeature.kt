package com.jielihome.jielihome.feature

import com.jieli.bluetooth.constant.ErrorCode
import com.jieli.bluetooth.impl.JL_BluetoothManager

class ScanFeature(private val btManager: JL_BluetoothManager) {

    fun startScan(timeoutMs: Int): Result<Unit> {
        val code = btManager.scan(timeoutMs)
        return if (code == ErrorCode.ERR_NONE) Result.success(Unit)
        else Result.failure(IllegalStateException("scan returned $code"))
    }

    fun stopScan() {
        btManager.stopScan()
    }

    fun isScanning(): Boolean = btManager.bluetoothOperation.isScanning
}
