package com.aiagent.device_plugin_interface

/** 设备能力（与 Dart [DeviceCapability] 一一对应）。 */
enum class DeviceCapability {
    SCAN,
    CONNECT,
    BOND,
    BATTERY,
    RSSI,
    OTA,
    EQ,
    ANC,
    KEY_MAPPING,
    WEAR_DETECTION,
    MIC_UPLINK,
    SPEAKER_DOWNLINK,
    WAKE_WORD,
    ON_DEVICE_CALL_TRANSLATION,
    ON_DEVICE_FACE_TO_FACE_TRANSLATION,
    ON_DEVICE_RECORDING_TRANSLATION,
    CUSTOM_COMMAND,
}

/** 连接状态机（与 Dart [DeviceConnectionState] 一一对应）。 */
enum class DeviceConnectionState {
    DISCONNECTED,
    CONNECTING,
    LINK_CONNECTED,
    READY,
    DISCONNECTING,
}

/** 厂商插件初始化配置。 */
data class DevicePluginConfig(
    val appKey: String? = null,
    val appSecret: String? = null,
    val extra: Map<String, Any?> = emptyMap(),
) {
    companion object {
        fun fromMap(map: Map<*, *>?): DevicePluginConfig {
            if (map == null) return DevicePluginConfig()
            return DevicePluginConfig(
                appKey = map["appKey"] as? String,
                appSecret = map["appSecret"] as? String,
                extra = (map["extra"] as? Map<*, *>)
                    ?.entries
                    ?.associate { it.key.toString() to it.value }
                    ?: emptyMap(),
            )
        }
    }
}

/** 扫描过滤条件。 */
data class DeviceScanFilter(
    val namePrefix: String? = null,
    val serviceUuids: List<String>? = null,
    val vendor: String? = null,
    val minRssi: Int? = null,
) {
    companion object {
        fun fromMap(map: Map<*, *>?): DeviceScanFilter? {
            if (map == null) return null
            @Suppress("UNCHECKED_CAST")
            return DeviceScanFilter(
                namePrefix = map["namePrefix"] as? String,
                serviceUuids = (map["serviceUuids"] as? List<*>)?.map { it.toString() },
                vendor = map["vendor"] as? String,
                minRssi = (map["minRssi"] as? Number)?.toInt(),
            )
        }
    }
}

/** 连接选项。 */
data class DeviceConnectOptions(
    val timeoutMs: Long = 15_000,
    val extra: Map<String, Any?> = emptyMap(),
) {
    companion object {
        fun fromMap(map: Map<*, *>?): DeviceConnectOptions {
            if (map == null) return DeviceConnectOptions()
            return DeviceConnectOptions(
                timeoutMs = (map["timeoutMs"] as? Number)?.toLong() ?: 15_000,
                extra = (map["extra"] as? Map<*, *>)
                    ?.entries
                    ?.associate { it.key.toString() to it.value }
                    ?: emptyMap(),
            )
        }
    }
}

/** 扫描发现的设备。 */
data class DiscoveredDevice(
    val id: String,
    val name: String,
    val rssi: Int? = null,
    val vendor: String? = null,
    val metadata: Map<String, Any?> = emptyMap(),
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "id" to id,
        "name" to name,
        "rssi" to rssi,
        "vendor" to vendor,
        "metadata" to metadata,
    )
}

/** 已连接设备的信息快照。 */
data class DeviceInfo(
    val id: String,
    val name: String,
    val vendor: String,
    val firmwareVersion: String? = null,
    val hardwareVersion: String? = null,
    val serialNumber: String? = null,
    val manufacturer: String? = null,
    val model: String? = null,
    val batteryPercent: Int? = null,
    val metadata: Map<String, Any?> = emptyMap(),
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "id" to id,
        "name" to name,
        "vendor" to vendor,
        "firmwareVersion" to firmwareVersion,
        "hardwareVersion" to hardwareVersion,
        "serialNumber" to serialNumber,
        "manufacturer" to manufacturer,
        "model" to model,
        "batteryPercent" to batteryPercent,
        "metadata" to metadata,
    )

    fun copyWith(
        name: String? = null,
        firmwareVersion: String? = null,
        hardwareVersion: String? = null,
        serialNumber: String? = null,
        manufacturer: String? = null,
        model: String? = null,
        batteryPercent: Int? = null,
        metadata: Map<String, Any?>? = null,
    ): DeviceInfo = DeviceInfo(
        id = id,
        vendor = vendor,
        name = name ?: this.name,
        firmwareVersion = firmwareVersion ?: this.firmwareVersion,
        hardwareVersion = hardwareVersion ?: this.hardwareVersion,
        serialNumber = serialNumber ?: this.serialNumber,
        manufacturer = manufacturer ?: this.manufacturer,
        model = model ?: this.model,
        batteryPercent = batteryPercent ?: this.batteryPercent,
        metadata = metadata ?: this.metadata,
    )
}

/** 唤醒原因（设备 → app）。 */
enum class WakeReason { PTT, VOICE_WAKE, TRANSLATE_KEY, HANGUP }

data class DeviceWakeEvent(
    val deviceId: String,
    val reason: WakeReason,
    val payload: Map<String, Any?> = emptyMap(),
)

/** 通用语义事件。`key` 命名空间：`common.<name>` / `<vendor>.<name>`。 */
data class DeviceFeatureEvent(
    val key: String,
    val data: Map<String, Any?> = emptyMap(),
)

/** 设备异常（plugin 抛出，路由器据此 emit error / 中断）。 */
class DeviceException(
    val code: String,
    message: String? = null,
    cause: Throwable? = null,
) : RuntimeException(message ?: code, cause)

/** 错误码命名空间。 */
object DeviceErrorCode {
    const val PERMISSION_DENIED = "device.permission_denied"
    const val BLUETOOTH_OFF = "device.bluetooth_off"
    const val CONNECT_TIMEOUT = "device.connect_timeout"
    const val CONNECT_FAILED = "device.connect_failed"
    const val HANDSHAKE_FAILED = "device.handshake_failed"
    const val DISCONNECTED_REMOTE = "device.disconnected_remote"
    const val AUDIO_BUSY = "device.audio_busy"
    const val NOT_SUPPORTED = "device.not_supported"
    const val FORMAT_UNSUPPORTED = "device.format_unsupported"
    const val VENDOR_SWITCHING = "device.vendor_switching"
    const val NO_ACTIVE_SESSION = "device.no_active_session"
    const val PLUGIN_NOT_INITIALIZED = "device.plugin_not_initialized"
    const val INVALID_ARGUMENT = "device.invalid_argument"
}
