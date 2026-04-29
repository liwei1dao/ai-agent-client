package com.aiagent.device_plugin_interface

import kotlinx.coroutines.flow.Flow

/**
 * 厂商插件 → 容器的事件类型。
 */
enum class DevicePluginEventType {
    PLUGIN_READY,
    PLUGIN_DISPOSED,
    BLUETOOTH_STATE_CHANGED,
    SCAN_STARTED,
    SCAN_STOPPED,
    DEVICE_DISCOVERED,
    BOND_STATE_CHANGED,
    CONNECTION_STATE_CHANGED,
    DEVICE_INFO_UPDATED,
    WAKE_TRIGGERED,
    CUSTOM_EVENT,
    ERROR,
}

data class DevicePluginEvent(
    val type: DevicePluginEventType,
    val deviceId: String? = null,
    val discovered: DiscoveredDevice? = null,
    val connectionState: DeviceConnectionState? = null,
    val deviceInfo: DeviceInfo? = null,
    val bluetoothEnabled: Boolean? = null,
    val bondState: String? = null, // 'none' | 'bonding' | 'bonded'
    val wake: DeviceWakeEvent? = null,
    val customKey: String? = null,
    val customPayload: Map<String, Any?>? = null,
    val errorCode: String? = null,
    val errorMessage: String? = null,
)

/**
 * 厂商插件 native 抽象（与 Dart [DevicePlugin] 等价）。
 *
 * 每家芯片/SDK 一份实现：
 *  - `JieliNativeDevicePlugin` (设备厂商：杰理)
 *  - 后续：恒玄 / 高通 / 中科蓝讯 等
 *
 * 实现方在自己 FlutterPlugin.onAttachedToEngine 时把工厂注册到
 * [NativeDevicePluginRegistry]，例如：
 * ```kotlin
 * NativeDevicePluginRegistry.register("jieli") { JieliNativeDevicePlugin(context) }
 * ```
 *
 * 容器 [NativeDeviceManager] 通过 vendorKey 查工厂，按需创建实例并管理生命周期。
 *
 * 铁律（与 Dart 接口完全对齐）：
 * 1. `initialize` 幂等；重复调用先释放旧资源。
 * 2. `dispose` 必须释放**所有** native 资源 + close 事件流。
 * 3. `dispose` 后任何方法抛 [IllegalStateException]。
 * 4. 通过 [eventStream]（[Flow]）派发事件，多订阅安全（用 `MutableSharedFlow.replay=0`）。
 */
interface NativeDevicePlugin {
    val vendorKey: String
    val displayName: String
    val capabilities: Set<DeviceCapability>

    /** 初始化 SDK；失败抛 [DeviceException]。 */
    fun initialize(config: DevicePluginConfig)

    fun startScan(filter: DeviceScanFilter? = null, timeoutMs: Long? = null)
    fun stopScan()
    fun isScanning(): Boolean

    /** 已配对设备快照（含历史/系统配对）。 */
    fun bondedDevices(): List<DiscoveredDevice>

    /**
     * 建立会话；必须在握手完成（state=READY）之后才 return；
     * 失败抛 [DeviceException]。
     */
    fun connect(deviceId: String, options: DeviceConnectOptions? = null): NativeDeviceSession

    /** 当前 active session（最多一个）。 */
    val activeSession: NativeDeviceSession?

    /** 全局事件流：扫描/连接/蓝牙开关/错误等。 */
    val eventStream: Flow<DevicePluginEvent>

    /** 释放 SDK + 断开所有 session + close stream。 */
    fun dispose()
}

/** 厂商插件工厂。 */
typealias NativeDevicePluginFactory = () -> NativeDevicePlugin

/**
 * 厂商插件全局注册表（参照 NativeAgentRegistry 模式）。
 *
 * 每个 device_<vendor> 包在自己的 FlutterPlugin.onAttachedToEngine 时注册一次工厂，
 * 容器 [NativeDeviceManager] 通过 vendorKey 创建实例。
 */
object NativeDevicePluginRegistry {

    private val factories = mutableMapOf<String, NativeDevicePluginFactory>()
    private val descriptors = mutableMapOf<String, VendorDescriptor>()

    /** 注册厂商（重复 register 用新工厂覆盖旧的）。 */
    fun register(
        vendorKey: String,
        displayName: String,
        capabilities: Set<DeviceCapability>,
        factory: NativeDevicePluginFactory,
    ) {
        factories[vendorKey] = factory
        descriptors[vendorKey] = VendorDescriptor(
            vendorKey = vendorKey,
            displayName = displayName,
            capabilities = capabilities,
        )
    }

    fun unregister(vendorKey: String) {
        factories.remove(vendorKey)
        descriptors.remove(vendorKey)
    }

    fun create(vendorKey: String): NativeDevicePlugin {
        val f = factories[vendorKey]
            ?: throw DeviceException(
                DeviceErrorCode.NOT_SUPPORTED,
                "vendor \"$vendorKey\" not registered. Available: ${factories.keys}",
            )
        return f()
    }

    fun listVendors(): List<VendorDescriptor> = descriptors.values.toList()

    fun isRegistered(vendorKey: String): Boolean = factories.containsKey(vendorKey)
}

/** 用于 listVendors() 给上层 UI 渲染下拉选项。 */
data class VendorDescriptor(
    val vendorKey: String,
    val displayName: String,
    val capabilities: Set<DeviceCapability>,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "vendorKey" to vendorKey,
        "displayName" to displayName,
        "capabilities" to capabilities.map { it.name },
    )
}
