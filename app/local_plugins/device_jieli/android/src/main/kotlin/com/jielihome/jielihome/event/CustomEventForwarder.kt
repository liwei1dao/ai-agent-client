package com.jielihome.jielihome.event

import android.bluetooth.BluetoothDevice
import android.util.Base64
import com.jieli.bluetooth.impl.JL_BluetoothManager
import com.jieli.bluetooth.interfaces.rcsp.callback.OnRcspEventListener
import com.jielihome.jielihome.bridge.EventDispatcher

/**
 * 厂商私有协议入口。
 * SDK 将所有未在内置协议表中匹配的「设备主动推」事件统一从 onExpandFunction 抛出，
 * 这里把它原样透传到 Dart（payload 走 base64），由业务层自行解析。
 *
 * 适用：自定义指令的设备->APP 反向通知，例如「检测到唤醒词」「自定义按键事件」。
 */
class CustomEventForwarder(
    private val btManager: JL_BluetoothManager,
    private val dispatcher: EventDispatcher,
) {
    private val listener = object : OnRcspEventListener() {
        override fun onExpandFunction(device: BluetoothDevice?, opCode: Int, payload: ByteArray?) {
            dispatcher.send(
                mapOf(
                    "type" to "expandFunction",
                    "address" to device?.address,
                    "opCode" to opCode,
                    "payloadBase64" to payload?.let { Base64.encodeToString(it, Base64.NO_WRAP) }
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
