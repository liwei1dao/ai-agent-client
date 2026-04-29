package com.aiagent.device_plugin_interface

import kotlinx.coroutines.flow.Flow

/** 容器 → app 的聚合事件类型（与 Dart [DeviceManagerEventType] 对齐）。 */
enum class DeviceManagerEventType {
    MANAGER_READY,
    VENDOR_CHANGED,
    BLUETOOTH_STATE_CHANGED,
    SCAN_STARTED,
    SCAN_STOPPED,
    DEVICE_DISCOVERED,
    ACTIVE_SESSION_CHANGED,
    SESSION_EVENT,
    /**
     * 设备完整快照变化。**任何**改动（连接态、电量、固件、活跃 session 切换）
     * 都会产生一份新的快照供 Dart 直接 mirror，Dart 端不再做字段 diff。
     */
    SNAPSHOT_UPDATED,
    ERROR,
}

data class DeviceManagerEvent(
    val type: DeviceManagerEventType,
    val vendorKey: String? = null,
    val bluetoothEnabled: Boolean? = null,
    val discovered: DiscoveredDevice? = null,
    val activeDeviceId: String? = null,
    val sessionEvent: DeviceSessionEvent? = null,
    /**
     * SNAPSHOT_UPDATED / ACTIVE_SESSION_CHANGED / SESSION_EVENT 一律附带；null
     * 表示当前没有 active session（vendor 未选 / 已断开）。
     * 由 [com.aiagent.device_manager.DefaultNativeDeviceManager] 在每次状态变化
     * 时统一序列化，供 Dart MethodChannel facade 整体替换缓存。
     */
    val sessionSnapshot: Map<String, Any?>? = null,
    val errorCode: String? = null,
    val errorMessage: String? = null,
)

/** 设备触发 agent 的事件（PTT / 翻译键 / 挂断键）。 */
data class DeviceAgentTrigger(
    val deviceId: String,
    val kind: Kind,
    val payload: Map<String, Any?> = emptyMap(),
) {
    enum class Kind { CHAT, TRANSLATE, STOP }
}

/**
 * 设备路由器 native 抽象（与 Dart [DeviceManager] 等价）。
 *
 * 进程内单例（典型实现：[com.aiagent.device_manager.DefaultNativeDeviceManager]）。
 *
 * 单设备 / 单 vendor 模型：
 *  - [activeSession] 至多一个；新 [connect] 自动断开旧 session
 *  - [useVendor] 是原子操作：stopScan → disconnect → 旧 plugin.dispose →
 *    新 plugin.initialize → emit [DeviceManagerEventType.VENDOR_CHANGED]
 *  - 切换中所有 scan/connect 抛 [DeviceException]([DeviceErrorCode.VENDOR_SWITCHING])
 */
interface NativeDeviceManager {
    /** 当前 active vendor key；未选为 null。 */
    val activeVendor: String?

    val activeCapabilities: Set<DeviceCapability>

    val activeSession: NativeDeviceSession?

    /** 列出全部已注册的 vendor（来自 [NativeDevicePluginRegistry]）。 */
    fun listVendors(): List<VendorDescriptor>

    /** 切换到指定 vendor；vendor=null 等价于 [clearVendor]。 */
    fun useVendor(vendorKey: String, config: DevicePluginConfig)

    /** 清掉当前 vendor：disconnect → dispose 当前 plugin。 */
    fun clearVendor()

    fun startScan(filter: DeviceScanFilter? = null, timeoutMs: Long? = null)
    fun stopScan()
    fun bondedDevices(): List<DiscoveredDevice>

    fun connect(deviceId: String, options: DeviceConnectOptions? = null): NativeDeviceSession
    fun disconnect()

    /** 容器级聚合事件流（多订阅安全）。 */
    val eventStream: Flow<DeviceManagerEvent>

    /** 设备主动触发 agent 的事件流。 */
    val agentTriggers: Flow<DeviceAgentTrigger>

    fun initialize()
    fun dispose()
}
