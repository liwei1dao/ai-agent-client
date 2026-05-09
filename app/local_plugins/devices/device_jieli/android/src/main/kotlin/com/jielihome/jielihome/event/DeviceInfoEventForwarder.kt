package com.jielihome.jielihome.event

import android.bluetooth.BluetoothDevice
import com.jieli.bluetooth.bean.base.VoiceMode
import com.jieli.bluetooth.bean.device.DevBroadcastMsg
import com.jieli.bluetooth.bean.device.status.BatteryInfo
import com.jieli.bluetooth.bean.device.voice.VoiceFunc
import com.jieli.bluetooth.bean.response.ADVInfoResponse
import com.jieli.bluetooth.impl.JL_BluetoothManager
import com.jieli.bluetooth.impl.rcsp.RCSPController
import com.jieli.bluetooth.interfaces.rcsp.ITwsOp
import com.jieli.bluetooth.interfaces.rcsp.callback.OnRcspEventListener
import com.jieli.bluetooth.interfaces.rcsp.callback.OnTwsEventListener
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

    /**
     * TWS 广播事件 —— 设备主动推的左右耳 / 电仓电量与充电态。
     *
     * 事件源说明：杰理 RCSP 会通过两个回调把电量变化推上来——
     *  - `onDeviceBroadcast` 携带完整 [DevBroadcastMsg]（左/右/仓 + 各自充电态），
     *    一般在佩戴/收回/电量变化等"主动事件"时发；
     *  - `onDeviceSettingsInfo` 在 `getDeviceSettingsInfo` 主动查询的回调里发，
     *    类型 `type` 由查询时的位掩码决定（电量 mask 时携带 ADV）。
     *
     * 我们对两条路径做相同的归一化——派一帧 `twsBroadcast`，UI / session 收到
     * 后调一次 `refreshInfo` 重新合并到 [com.aiagent.device_plugin_interface.DeviceInfo]。
     * 业务层不需要懂广播协议，只需订阅 device_session 的 deviceInfoUpdated。
     */
    private val twsListener = object : OnTwsEventListener() {
        override fun onDeviceBroadcast(device: BluetoothDevice?, msg: DevBroadcastMsg?) {
            if (device == null || msg == null) return
            dispatcher.send(buildTwsPayload(device.address, msg))
        }

        override fun onDeviceSettingsInfo(
            device: BluetoothDevice?,
            type: Int,
            adv: ADVInfoResponse?,
        ) {
            if (device == null || adv == null) return
            dispatcher.send(buildTwsPayload(device.address, adv))
        }
    }

    fun attach() {
        btManager.registerOnRcspEventListener(listener)
        // RCSPController 通过多层继承实现了 [ITwsOp]，强转拿到接口注册 listener。
        // 这里用安全 cast：极端情况下 SDK 内部还没 init 完时不应该崩。
        val twsOp = RCSPController.getInstance() as? ITwsOp
        twsOp?.addOnTwsEventListener(twsListener)
    }

    fun detach() {
        btManager.unregisterOnRcspEventListener(listener)
        val twsOp = RCSPController.getInstance() as? ITwsOp
        twsOp?.removeOnTwsEventListener(twsListener)
    }

    /** 把两种广播 / settings 来源的数据归一成同一份 payload。 */
    private fun buildTwsPayload(address: String, src: Any): Map<String, Any?> {
        val (left, right, case, lc, rc, dc) = when (src) {
            is DevBroadcastMsg -> TwsTuple(
                src.leftDeviceQuantity, src.rightDeviceQuantity,
                src.chargingBinQuantity,
                src.isLeftCharging, src.isRightCharging, src.isDeviceCharging,
            )
            is ADVInfoResponse -> TwsTuple(
                src.leftDeviceQuantity, src.rightDeviceQuantity,
                src.chargingBinQuantity,
                src.isLeftCharging, src.isRightCharging, src.isDeviceCharging,
            )
            else -> return emptyMap()
        }
        return mapOf(
            "type" to "twsBroadcast",
            "address" to address,
            "leftBattery" to left.normalizeBattery(),
            "rightBattery" to right.normalizeBattery(),
            "caseBattery" to case.normalizeBattery(),
            "leftCharging" to lc,
            "rightCharging" to rc,
            "caseCharging" to dc,
        )
    }
}

private data class TwsTuple(
    val left: Int, val right: Int, val case: Int,
    val leftCharging: Boolean, val rightCharging: Boolean, val caseCharging: Boolean,
)

private fun Int.normalizeBattery(): Int? = takeIf { it in 0..100 }
