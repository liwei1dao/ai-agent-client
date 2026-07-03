package com.jielihome.jielihome.feature

import android.bluetooth.BluetoothDevice
import android.util.Log
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

    companion object {
        private const val TAG = "CustomCmdFeature"
    }

    fun send(
        address: String,
        opCode: Int,
        payload: ByteArray,
        onSuccess: (ByteArray?) -> Unit,
        onError: (Int, String?) -> Unit,
    ) {
        val device: BluetoothDevice = BluetoothUtil.getRemoteDevice(address)
            ?: return onError(-1, "remote device not found")

        Log.i(TAG, "[APP->SDK] sendRcspCommand addr=$address opCode=$opCode(0x${String.format("%02X", opCode)}) payloadSize=${payload.size}")
        val cmd = CustomCmd(opCode, CustomParam(payload))
        btManager.sendRcspCommand(device, cmd, object : RcspCommandCallback {
            override fun onCommandResponse(dev: BluetoothDevice?, resp: CommandBase<*, *>?) {
                val r = resp?.response as? CustomResponse
                Log.i(TAG, "[SDK<-DEV] sendRcspCommand onResponse addr=${dev?.address} opCode=$opCode dataSize=${r?.data?.size ?: 0}")
                onSuccess(r?.data)
            }

            override fun onErrCode(dev: BluetoothDevice?, err: BaseError?) {
                Log.w(TAG, "[SDK<-DEV] sendRcspCommand onErrCode addr=${dev?.address} opCode=$opCode code=${err?.code} msg=${err?.message}")
                onError(err?.code ?: -2, err?.message)
            }
        })
    }
}
