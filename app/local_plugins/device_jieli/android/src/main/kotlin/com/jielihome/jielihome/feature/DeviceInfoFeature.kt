package com.jielihome.jielihome.feature

import android.bluetooth.BluetoothDevice
import com.jieli.bluetooth.bean.base.BaseError
import com.jieli.bluetooth.bean.base.CommandBase
import com.jieli.bluetooth.bean.command.GetTargetInfoCmd
import com.jieli.bluetooth.bean.parameter.GetTargetInfoParam
import com.jieli.bluetooth.bean.response.ADVInfoResponse
import com.jieli.bluetooth.bean.response.TargetInfoResponse
import com.jieli.bluetooth.impl.JL_BluetoothManager
import com.jieli.bluetooth.interfaces.bluetooth.RcspCommandCallback
import com.jieli.bluetooth.interfaces.rcsp.ITwsOp
import com.jieli.bluetooth.utils.BluetoothUtil

/**
 * 查询电量、版本号等设备静态信息（拉取式）。
 * 设备主动推的电量变化由 DeviceInfoEventForwarder 处理。
 *
 * **电量字段语义**（[snapshot] 输出）：
 * - `battery`：SDK 聚合后的总电量（来自 `BatteryInfo.battery` / `TargetInfoResponse.quantity`），
 *   兼容旧字段，单设备/非 TWS 设备只有这一项。
 * - `batteryLeft` / `batteryRight` / `batteryCase`：来自 [ITwsOp.getADVInfo]
 *   解析的 ADV 广播；TWS 双耳耳机才有，旧固件 / 非 TWS 设备这三个字段为 null。
 * - `chargingLeft` / `chargingRight` / `chargingCase`：对应位置的充电状态；
 *   `getADVInfo` 返回 null 时（非 TWS）这三个字段也为 null。
 *
 * 上层 [com.jielihome.jielihome.integration.JieliNativeDeviceSession] 负责把这些
 * 字段映射成接口层 `DeviceInfo` 的 `batteryLeft/batteryRight/batteryCase/chargingX`，
 * 业务层不需要知道杰理的协议细节。
 */
class DeviceInfoFeature(private val btManager: JL_BluetoothManager) {

    /** 直接读 SDK 缓存（连接成功后已自动拉取过一次） */
    fun snapshot(address: String): Map<String, Any?>? {
        val device = BluetoothUtil.getRemoteDevice(address) ?: return null
        val info = btManager.getDeviceInfo(device) ?: return null
        val base = mutableMapOf<String, Any?>(
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
            "edrAddr" to info.edrAddr,
        )
        // 合并 TWS ADV 广播信息——非 TWS / 旧固件返回 null，跳过即可，旧字段
        // `battery` 仍然有效作为 fallback。
        try {
            val twsOp = com.jieli.bluetooth.impl.rcsp.RCSPController.getInstance()
                as? ITwsOp
            val adv: ADVInfoResponse? = twsOp?.getADVInfo(device)
            if (adv != null) {
                base["batteryLeft"] = adv.leftDeviceQuantity.normalizeBattery()
                base["batteryRight"] = adv.rightDeviceQuantity.normalizeBattery()
                base["batteryCase"] = adv.chargingBinQuantity.normalizeBattery()
                // SDK 把"是否处于充电态"分开三档：左 / 右 / 整机（实际指充电仓）。
                // 非 TWS 时仍可能给到 deviceCharging（单设备充电），保留语义。
                base["chargingLeft"] = adv.isLeftCharging
                base["chargingRight"] = adv.isRightCharging
                base["chargingCase"] = adv.isDeviceCharging
            }
        } catch (e: Throwable) {
            // SDK 内部偶发空指针 / 未初始化时不应阻塞 snapshot 整体返回——只丢失
            // 左右耳量信息，base 仍然能给出总电量。
            android.util.Log.w("DeviceInfoFeature", "getADVInfo failed: ${e.message}")
        }
        return base
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

/**
 * SDK 的 quantity 字段在未上报 / 不支持时给 0xFF（255）作为"未知"哨兵；
 * 真实电量范围是 0..100。把 0xFF / 越界值统一映射为 null，让上层走"不显示
 * 该位置"的分支。注意 0 是合法值（电量耗尽），不能丢。
 */
private fun Int.normalizeBattery(): Int? = takeIf { it in 0..100 }
