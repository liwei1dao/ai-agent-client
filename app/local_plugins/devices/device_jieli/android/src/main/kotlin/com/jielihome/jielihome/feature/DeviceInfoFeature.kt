package com.jielihome.jielihome.feature

import android.bluetooth.BluetoothDevice
import com.jieli.bluetooth.bean.base.BaseError
import com.jieli.bluetooth.bean.base.CommandBase
import com.jieli.bluetooth.bean.command.GetTargetInfoCmd
import com.jieli.bluetooth.bean.parameter.GetTargetInfoParam
import com.jieli.bluetooth.bean.response.TargetInfoResponse
import com.jieli.bluetooth.impl.JL_BluetoothManager
import com.jieli.bluetooth.interfaces.bluetooth.RcspCommandCallback
import com.jieli.bluetooth.utils.BluetoothUtil

/**
 * 查询电量、版本号等设备静态信息（拉取式）。
 * 设备主动推的电量变化由 DeviceInfoEventForwarder 处理。
 */
class DeviceInfoFeature(private val btManager: JL_BluetoothManager) {

    /** 直接读 SDK 缓存（连接成功后已自动拉取过一次） */
    fun snapshot(address: String): Map<String, Any?>? {
        val device = BluetoothUtil.getRemoteDevice(address) ?: return null
        val info = btManager.getDeviceInfo(device) ?: return null
        return mapOf(
            "address" to device.address,
            "battery" to info.quantity,
            "volume" to info.volume,
            "maxVolume" to info.maxVol,
            "versionCode" to info.versionCode,
            "versionName" to info.versionName,
            "name" to info.name,
            "vid" to info.vid,
            "pid" to info.pid,
            "uid" to info.uid,
            "edrAddr" to info.edrAddr
        )
    }

    /**
     * 主动向设备发指令拉取最新 TargetInfo。
     * @param mask 设备字段位掩码，常见 0x0F 拉常用字段；具体 mask 见杰理协议文档
     */
    fun queryTargetInfo(
        address: String,
        mask: Int,
        onSuccess: (Map<String, Any?>) -> Unit,
        onError: (Int, String?) -> Unit,
    ) {
        val device: BluetoothDevice = BluetoothUtil.getRemoteDevice(address)
            ?: return onError(-1, "remote device not found")

        val cmd = GetTargetInfoCmd(GetTargetInfoParam(mask))
        btManager.sendRcspCommand(device, cmd, object : RcspCommandCallback {
            override fun onCommandResponse(dev: BluetoothDevice?, resp: CommandBase<*, *>?) {
                val r = resp?.response as? TargetInfoResponse
                    ?: return onError(-2, "no response")
                onSuccess(
                    mapOf(
                        "address" to (dev?.address ?: address),
                        "battery" to r.quantity,
                        "volume" to r.volume,
                        "versionCode" to r.versionCode,
                        "versionName" to r.versionName,
                        "name" to r.name
                    )
                )
            }

            override fun onErrCode(dev: BluetoothDevice?, err: BaseError?) {
                onError(err?.code ?: -3, err?.message)
            }
        })
    }
}
