package com.jielihome.jielihome.feature

import android.bluetooth.BluetoothDevice
import com.jieli.bluetooth.bean.base.BaseError
import com.jieli.bluetooth.bean.base.CommandBase
import com.jieli.bluetooth.bean.command.custom.CustomCmd
import com.jieli.bluetooth.bean.parameter.CustomParam
import com.jieli.bluetooth.bean.response.CustomResponse
import com.jieli.bluetooth.impl.JL_BluetoothManager
import com.jieli.bluetooth.interfaces.bluetooth.RcspCommandCallback
import com.jieli.bluetooth.utils.BluetoothUtil

/**
 * 厂商扩展指令通道。
 * 用法：业务方约定一个 opCode + payload 字节流，从这里下发；设备应答的 payload 透传回 Dart。
 * 设备「主动推」的扩展事件由 CustomEventForwarder.onExpandFunction 接收。
 */
class CustomCmdFeature(private val btManager: JL_BluetoothManager) {

    fun send(
        address: String,
        opCode: Int,
        payload: ByteArray,
        onSuccess: (ByteArray?) -> Unit,
        onError: (Int, String?) -> Unit,
    ) {
        val device: BluetoothDevice = BluetoothUtil.getRemoteDevice(address)
            ?: return onError(-1, "remote device not found")

        val cmd = CustomCmd(opCode, CustomParam(payload))
        btManager.sendRcspCommand(device, cmd, object : RcspCommandCallback {
            override fun onCommandResponse(dev: BluetoothDevice?, resp: CommandBase<*, *>?) {
                val r = resp?.response as? CustomResponse
                onSuccess(r?.data)
            }

            override fun onErrCode(dev: BluetoothDevice?, err: BaseError?) {
                onError(err?.code ?: -2, err?.message)
            }
        })
    }
}
