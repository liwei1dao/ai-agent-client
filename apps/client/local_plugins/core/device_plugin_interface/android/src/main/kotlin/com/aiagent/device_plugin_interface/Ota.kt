package com.aiagent.device_plugin_interface

import kotlinx.coroutines.flow.Flow

/**
 * OTA 升级请求 —— 多态请求层级（与 Dart [DeviceOtaRequest] 对齐）。
 *
 * 业务层只构造其中一种子类；插件实现按 `when` 分派。
 * 厂商不支持的子类一律抛 [DeviceException]([DeviceErrorCode.NOT_SUPPORTED])，
 * **禁止**静默退化（业务侧才有"是否回退到本地下载"的语义）。
 */
sealed class DeviceOtaRequest {
    /** 单块大小。null = 走厂商默认。 */
    abstract val blockSize: Int?

    /** 整段 OTA 的超时；null = 不限。 */
    abstract val timeoutMs: Long?

    /** 本地文件：app 自己下载好后放在沙盒里。 */
    data class File(
        val filePath: String,
        override val blockSize: Int? = null,
        override val timeoutMs: Long? = null,
    ) : DeviceOtaRequest()

    /** 内存字节流：固件已经在内存里。 */
    data class Bytes(
        val bytes: ByteArray,
        override val blockSize: Int? = null,
        override val timeoutMs: Long? = null,
    ) : DeviceOtaRequest() {
        override fun equals(other: Any?): Boolean =
            this === other || (other is Bytes && bytes.contentEquals(other.bytes))
        override fun hashCode(): Int = bytes.contentHashCode()
    }

    /** 远程 URL：让 native 自己下载；不支持时抛 NOT_SUPPORTED 由调用方退回。 */
    data class Url(
        val url: String,
        val headers: Map<String, String> = emptyMap(),
        override val blockSize: Int? = null,
        override val timeoutMs: Long? = null,
    ) : DeviceOtaRequest()

    /** 厂商扩展：差分包 / 双备份 / fileFlag 等私有参数。 */
    data class Vendor(
        val vendorKey: String,
        val payload: Map<String, Any?>,
        override val blockSize: Int? = null,
        override val timeoutMs: Long? = null,
    ) : DeviceOtaRequest()

    companion object {
        /**
         * 从 method channel map 反序列化（kind 字段做 tag）。
         * 不识别的 kind 抛 [DeviceException]([DeviceErrorCode.INVALID_ARGUMENT])。
         */
        @Suppress("UNCHECKED_CAST")
        fun fromMap(map: Map<*, *>): DeviceOtaRequest {
            val kind = map["kind"] as? String
                ?: throw DeviceException(DeviceErrorCode.INVALID_ARGUMENT, "ota: kind required")
            val blockSize = (map["blockSize"] as? Number)?.toInt()
            val timeoutMs = (map["timeoutMs"] as? Number)?.toLong()
            return when (kind) {
                "file" -> File(
                    filePath = map["filePath"] as? String
                        ?: throw DeviceException(DeviceErrorCode.INVALID_ARGUMENT, "ota.file: filePath required"),
                    blockSize = blockSize,
                    timeoutMs = timeoutMs,
                )
                "bytes" -> Bytes(
                    bytes = (map["bytes"] as? ByteArray)
                        ?: throw DeviceException(DeviceErrorCode.INVALID_ARGUMENT, "ota.bytes: bytes required"),
                    blockSize = blockSize,
                    timeoutMs = timeoutMs,
                )
                "url" -> Url(
                    url = map["url"] as? String
                        ?: throw DeviceException(DeviceErrorCode.INVALID_ARGUMENT, "ota.url: url required"),
                    headers = (map["headers"] as? Map<String, String>) ?: emptyMap(),
                    blockSize = blockSize,
                    timeoutMs = timeoutMs,
                )
                "vendor" -> Vendor(
                    vendorKey = map["vendorKey"] as? String
                        ?: throw DeviceException(DeviceErrorCode.INVALID_ARGUMENT, "ota.vendor: vendorKey required"),
                    payload = (map["payload"] as? Map<String, Any?>) ?: emptyMap(),
                    blockSize = blockSize,
                    timeoutMs = timeoutMs,
                )
                else -> throw DeviceException(
                    DeviceErrorCode.INVALID_ARGUMENT,
                    "ota: unknown kind \"$kind\"",
                )
            }
        }
    }
}

/** OTA 全局状态机（与 Dart [DeviceOtaState] 一一对应）。 */
enum class DeviceOtaState {
    IDLE,
    /** 容器层下载远程固件中（Url 请求专属，厂商插件看不到）。 */
    DOWNLOADING,
    INQUIRING,
    NOTIFYING_SIZE,
    ENTERING,
    TRANSFERRING,
    VERIFYING,
    REBOOTING,
    DONE,
    FAILED,
    CANCELLED,
}

/** OTA 进度事件。 */
data class DeviceOtaProgress(
    val state: DeviceOtaState,
    val sentBytes: Long,
    val totalBytes: Long,
    /** 0..100；未知或非 transferring 阶段可为 -1。 */
    val percent: Int,
    val tsMs: Long,
    /** 终态时携带错误码（state ∈ {FAILED}）；其它阶段为 null。 */
    val errorCode: String? = null,
    val errorMessage: String? = null,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "state" to state.name,
        "sentBytes" to sentBytes,
        "totalBytes" to totalBytes,
        "percent" to percent,
        "tsMs" to tsMs,
        "errorCode" to errorCode,
        "errorMessage" to errorMessage,
    )

    val isTerminal: Boolean
        get() = state == DeviceOtaState.DONE ||
                state == DeviceOtaState.FAILED ||
                state == DeviceOtaState.CANCELLED
}

/**
 * OTA 端口（同 [DeviceCallTranslationPort] 的设计风格）。
 *
 * 单设备 OTA 互斥：同时只能跑一个 [start]，重复 start 抛
 * [DeviceException]([DeviceErrorCode.OTA_BUSY])。
 *
 * 生命周期与铁律：
 * 1. `start` 之后 [progressStream] 必有终态（DONE/FAILED/CANCELLED），不得悬挂；
 * 2. 设备掉线时端口须主动派 FAILED 收尾；
 * 3. `cancel` 后短时间内（≤ 5s）须收到 CANCELLED；超时强制收尾；
 * 4. **不**要求支持断点续传，但若实现了须在 SDK 内部完成，对外只露统一进度。
 */
interface DeviceOtaPort {
    fun start(request: DeviceOtaRequest)
    fun cancel()
    val isRunning: Boolean
    val progressStream: Flow<DeviceOtaProgress>
}

/** OTA 错误码补充（与 Dart 镜像）。 */
object OtaErrorCode {
    const val BUSY = DeviceErrorCode.OTA_BUSY
    const val INQUIRE_REFUSED = DeviceErrorCode.OTA_INQUIRE_REFUSED
    const val VERIFY_FAILED = DeviceErrorCode.OTA_VERIFY_FAILED
    const val FILE_INVALID = DeviceErrorCode.OTA_FILE_INVALID
    const val TRANSFER_FAILED = DeviceErrorCode.OTA_TRANSFER_FAILED
}
