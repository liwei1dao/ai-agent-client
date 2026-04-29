package com.aiagent.device_plugin_interface

import kotlinx.coroutines.flow.Flow

/** 单设备会话事件类型（与 Dart [DeviceSessionEventType] 对齐）。 */
enum class DeviceSessionEventType {
    CONNECTION_STATE_CHANGED,
    DEVICE_INFO_UPDATED,
    FEATURE,
    RSSI_UPDATED,
    RAW,
    ERROR,
}

data class DeviceSessionEvent(
    val type: DeviceSessionEventType,
    val deviceId: String,
    val connectionState: DeviceConnectionState? = null,
    val deviceInfo: DeviceInfo? = null,
    val feature: DeviceFeatureEvent? = null,
    val rssi: Int? = null,
    val raw: Map<String, Any?>? = null,
    val errorCode: String? = null,
    val errorMessage: String? = null,
)

/**
 * 已连接设备的 native 会话句柄（与 Dart [DeviceSession] 等价）。
 *
 * 生命周期：connecting → linkConnected → ready → (业务调用) → disconnecting → disconnected
 *
 * 铁律：
 * 1. `disconnected` 之后任何方法抛 [IllegalStateException]
 * 2. [eventStream] 是 broadcast / multi-subscriber-safe
 * 3. [invokeFeature] / [readBattery] / [refreshInfo] 在状态非 READY 时抛
 *    [DeviceException]([DeviceErrorCode.NO_ACTIVE_SESSION])，禁止静默排队
 */
interface NativeDeviceSession {
    val deviceId: String
    val vendor: String
    val state: DeviceConnectionState
    val info: DeviceInfo
    val capabilities: Set<DeviceCapability>

    val eventStream: Flow<DeviceSessionEvent>

    fun readRssi(): Int

    /** 读电量；不支持时返回 null（不抛）。 */
    fun readBattery(): Int?

    /** 强制刷新 [DeviceInfo]（电量/固件版本/序列号）。 */
    fun refreshInfo(): DeviceInfo

    /**
     * 调用厂商私有 feature。`featureKey` 形如：
     * - `common.battery.subscribe`
     * - `jieli.translation.start`
     * - `bes.eq.set`
     */
    fun invokeFeature(featureKey: String, args: Map<String, Any?> = emptyMap()): Map<String, Any?>

    /**
     * 该 session 暴露的通话翻译端口；vendor 无该能力时返回 null。
     *
     * 给 native 编排器（translate_server）vendor-agnostic 拿端口的入口——
     * 编排器只调本接口，不需要 import 任何具体厂商类型。
     */
    fun callTranslationPort(): DeviceCallTranslationPort? = null

    fun disconnect()
}
