package com.jielihome.jielihome.integration

import android.util.Log
import com.aiagent.device_plugin_interface.DeviceErrorCode
import com.aiagent.device_plugin_interface.DeviceException
import com.aiagent.device_plugin_interface.DeviceOtaPort
import com.aiagent.device_plugin_interface.DeviceOtaProgress
import com.aiagent.device_plugin_interface.DeviceOtaRequest
import com.aiagent.device_plugin_interface.DeviceOtaState
import com.jielihome.jielihome.api.JieliEventAdapter
import com.jielihome.jielihome.api.JieliEventListener
import com.jielihome.jielihome.core.JieliHomeServer
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

/**
 * 杰理 [DeviceOtaPort] 实现 —— 桥接 [com.jielihome.jielihome.feature.ota.OtaFeature]。
 *
 * 不重写 OtaFeature 的状态机，只把它派的 `otaState` / `otaError` 事件翻译成
 * [DeviceOtaProgress] 推到 [progressStream]。
 *
 * 请求子类支持矩阵：
 * - [DeviceOtaRequest.File]   ✓ 直接 path 传给 OtaFeature
 * - [DeviceOtaRequest.Bytes]  ✓ 落盘到 cacheDir/ota_<ts>.ufw 再走 path
 * - [DeviceOtaRequest.Url]    ✗ 杰理 SDK 无 HTTP 通道，抛 NOT_SUPPORTED
 * - [DeviceOtaRequest.Vendor] ✓ payload['filePath'] + payload['fileFlag'] 透传
 *
 * 端口生命周期：
 * - session disconnect 时由 [JieliNativeDeviceSession] 调 [shutdown] —— 主动 cancel +
 *   补一帧 FAILED(disconnected_remote) 让上层取消订阅 / 跳出锁定 UI。
 */
class JieliOtaPort internal constructor(
    private val server: JieliHomeServer,
    private val deviceId: String,
    private val cacheDir: File,
) : DeviceOtaPort {

    companion object {
        private const val TAG = "JieliOtaPort"
    }

    private val _running = AtomicBoolean(false)
    @Volatile private var _totalBytes: Long = 0
    @Volatile private var _tempFile: File? = null
    @Volatile private var _disposed = false

    private val _progress = MutableSharedFlow<DeviceOtaProgress>(
        replay = 1,
        extraBufferCapacity = 32,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )

    override val progressStream: Flow<DeviceOtaProgress> = _progress.asSharedFlow()

    override val isRunning: Boolean get() = _running.get() || server.otaFeature.isRunning()

    private val listener: JieliEventListener = object : JieliEventAdapter() {
        override fun onOtaState(payload: Map<String, Any?>) {
            val stateName = payload["state"] as? String ?: return
            val state = parseState(stateName) ?: return
            val sent = (payload["sent"] as? Number)?.toLong() ?: 0L
            val total = (payload["total"] as? Number)?.toLong() ?: _totalBytes
            val percent = (payload["percent"] as? Number)?.toInt() ?: -1
            val tsMs = (payload["tsMs"] as? Number)?.toLong() ?: System.currentTimeMillis()
            emit(DeviceOtaProgress(
                state = state,
                sentBytes = sent,
                totalBytes = total,
                percent = percent,
                tsMs = tsMs,
            ))
            if (state == DeviceOtaState.DONE ||
                state == DeviceOtaState.CANCELLED ||
                state == DeviceOtaState.FAILED) {
                finalize()
            }
        }

        override fun onOtaError(payload: Map<String, Any?>) {
            // OtaFeature 用整数 code；映射到 device.* 命名空间。
            val rawCode = (payload["code"] as? Number)?.toInt() ?: -1
            val msg = payload["message"] as? String
            val mapped = mapErrorCode(rawCode)
            emit(DeviceOtaProgress(
                state = DeviceOtaState.FAILED,
                sentBytes = -1,
                totalBytes = _totalBytes,
                percent = -1,
                tsMs = System.currentTimeMillis(),
                errorCode = mapped,
                errorMessage = msg,
            ))
        }
    }

    init {
        server.addEventListener(listener)
    }

    // ─── DeviceOtaPort ────────────────────────────────────────────────────

    @Synchronized
    override fun start(request: DeviceOtaRequest) {
        if (_disposed) throw DeviceException(DeviceErrorCode.NO_ACTIVE_SESSION)
        if (!_running.compareAndSet(false, true) || server.otaFeature.isRunning()) {
            _running.set(server.otaFeature.isRunning() || _running.get())
            throw DeviceException(DeviceErrorCode.OTA_BUSY, "ota already running")
        }
        val (path, fileFlag) = try {
            resolveFirmware(request)
        } catch (e: DeviceException) {
            _running.set(false)
            throw e
        } catch (t: Throwable) {
            _running.set(false)
            throw DeviceException(DeviceErrorCode.OTA_FILE_INVALID, t.message ?: "firmware error", t)
        }
        _totalBytes = File(path).length().coerceAtLeast(0L)

        // 立即派一帧 INQUIRING，UI 不必等 OtaFeature 第一次回调。
        emit(DeviceOtaProgress(
            state = DeviceOtaState.INQUIRING,
            sentBytes = 0,
            totalBytes = _totalBytes,
            percent = 0,
            tsMs = System.currentTimeMillis(),
        ))

        try {
            server.otaFeature.start(
                address = deviceId,
                firmwareFilePath = path,
                blockSize = request.blockSize ?: 512,
                fileFlagBytes = fileFlag,
            )
        } catch (t: Throwable) {
            _running.set(false)
            cleanupTemp()
            throw DeviceException(DeviceErrorCode.OTA_TRANSFER_FAILED, t.message, t)
        }
    }

    override fun cancel() {
        if (!_running.get() && !server.otaFeature.isRunning()) return
        server.otaFeature.cancel()
        // 状态变更通过 onOtaState(CANCELLED) 回到 finalize。
    }

    /** 由 [JieliNativeDeviceSession] 在 disconnect 时调用：补 FAILED 帧并解订阅。 */
    fun shutdown(reason: String = DeviceErrorCode.DISCONNECTED_REMOTE) {
        if (_disposed) return
        _disposed = true
        if (_running.get()) {
            runCatching { server.otaFeature.cancel() }
            emit(DeviceOtaProgress(
                state = DeviceOtaState.FAILED,
                sentBytes = -1,
                totalBytes = _totalBytes,
                percent = -1,
                tsMs = System.currentTimeMillis(),
                errorCode = reason,
                errorMessage = "session terminated during ota",
            ))
        }
        runCatching { server.removeEventListener(listener) }
        cleanupTemp()
        _running.set(false)
    }

    // ─── 内部 ──────────────────────────────────────────────────────────────

    private fun resolveFirmware(req: DeviceOtaRequest): Pair<String, ByteArray> {
        val flag = ByteArray(0) // OtaFeature 默认 fileFlag
        return when (req) {
            is DeviceOtaRequest.File -> {
                val f = File(req.filePath)
                if (!f.isFile || f.length() <= 0) {
                    throw DeviceException(
                        DeviceErrorCode.OTA_FILE_INVALID,
                        "firmware file invalid: ${req.filePath}",
                    )
                }
                req.filePath to flag
            }

            is DeviceOtaRequest.Bytes -> {
                if (req.bytes.isEmpty()) {
                    throw DeviceException(
                        DeviceErrorCode.OTA_FILE_INVALID,
                        "ota bytes empty",
                    )
                }
                if (!cacheDir.isDirectory && !cacheDir.mkdirs()) {
                    throw DeviceException(
                        DeviceErrorCode.OTA_FILE_INVALID,
                        "cannot create ota cache dir: ${cacheDir.absolutePath}",
                    )
                }
                val tmp = File(cacheDir, "ota_${System.currentTimeMillis()}.ufw")
                tmp.writeBytes(req.bytes)
                _tempFile = tmp
                tmp.absolutePath to flag
            }

            is DeviceOtaRequest.Url -> {
                throw DeviceException(
                    DeviceErrorCode.NOT_SUPPORTED,
                    "jieli ota does not support remote url; download in app and use File request",
                )
            }

            is DeviceOtaRequest.Vendor -> {
                if (req.vendorKey != "jieli") {
                    throw DeviceException(
                        DeviceErrorCode.INVALID_ARGUMENT,
                        "vendor mismatch: expected 'jieli', got '${req.vendorKey}'",
                    )
                }
                val path = req.payload["filePath"] as? String
                    ?: throw DeviceException(
                        DeviceErrorCode.INVALID_ARGUMENT,
                        "jieli ota.vendor: payload['filePath'] required",
                    )
                val f = File(path)
                if (!f.isFile || f.length() <= 0) {
                    throw DeviceException(
                        DeviceErrorCode.OTA_FILE_INVALID,
                        "firmware file invalid: $path",
                    )
                }
                @Suppress("UNCHECKED_CAST")
                val customFlag = (req.payload["fileFlag"] as? ByteArray)
                    ?: (req.payload["fileFlag"] as? List<Number>)?.map { it.toByte() }?.toByteArray()
                    ?: flag
                path to customFlag
            }
        }
    }

    private fun finalize() {
        _running.set(false)
        cleanupTemp()
    }

    private fun cleanupTemp() {
        _tempFile?.let { runCatching { it.delete() } }
        _tempFile = null
    }

    private fun emit(p: DeviceOtaProgress) {
        if (!_progress.tryEmit(p)) Log.w(TAG, "progress buffer full; dropped ${p.state}")
    }

    private fun parseState(name: String): DeviceOtaState? = when (name) {
        "IDLE" -> DeviceOtaState.IDLE
        "INQUIRING" -> DeviceOtaState.INQUIRING
        "NOTIFYING_SIZE" -> DeviceOtaState.NOTIFYING_SIZE
        "ENTERING" -> DeviceOtaState.ENTERING
        "TRANSFERRING" -> DeviceOtaState.TRANSFERRING
        "VERIFYING" -> DeviceOtaState.VERIFYING
        "REBOOTING" -> DeviceOtaState.REBOOTING
        "DONE" -> DeviceOtaState.DONE
        "FAILED" -> DeviceOtaState.FAILED
        "CANCELLED" -> DeviceOtaState.CANCELLED
        else -> null
    }

    /** OtaFeature 的负数错误码映射到设备域命名空间。 */
    private fun mapErrorCode(raw: Int): String = when (raw) {
        -1 -> DeviceErrorCode.OTA_BUSY
        -2 -> DeviceErrorCode.NO_ACTIVE_SESSION
        -3 -> DeviceErrorCode.OTA_FILE_INVALID
        -100 -> DeviceErrorCode.OTA_TRANSFER_FAILED
        else -> DeviceErrorCode.OTA_TRANSFER_FAILED
    }
}
