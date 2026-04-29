package com.jielihome.jielihome.feature.ota

import android.bluetooth.BluetoothDevice
import com.jieli.bluetooth.bean.base.BaseError
import com.jieli.bluetooth.bean.base.CommandBase
import com.jieli.bluetooth.bean.command.ota.EnterUpdateModeCmd
import com.jieli.bluetooth.bean.command.ota.ExitUpdateModeCmd
import com.jieli.bluetooth.bean.command.ota.FirmwareUpdateBlockCmd
import com.jieli.bluetooth.bean.command.ota.FirmwareUpdateStatusCmd
import com.jieli.bluetooth.bean.command.ota.GetUpdateFileOffsetCmd
import com.jieli.bluetooth.bean.command.ota.InquireUpdateCmd
import com.jieli.bluetooth.bean.command.ota.NotifyUpdateContentSizeCmd
import com.jieli.bluetooth.bean.command.ota.RebootDeviceCmd
import com.jieli.bluetooth.bean.parameter.FirmwareUpdateBlockParam
import com.jieli.bluetooth.bean.parameter.InquireUpdateParam
import com.jieli.bluetooth.bean.parameter.NotifyUpdateContentSizeParam
import com.jieli.bluetooth.bean.parameter.RebootDeviceParam
import com.jieli.bluetooth.bean.response.EnterUpdateModeResponse
import com.jieli.bluetooth.bean.response.FirmwareUpdateBlockResponse
import com.jieli.bluetooth.bean.response.FirmwareUpdateStatusResponse
import com.jieli.bluetooth.bean.response.InquireUpdateResponse
import com.jieli.bluetooth.bean.response.UpdateFileOffsetResponse
import com.jieli.bluetooth.impl.JL_BluetoothManager
import com.jieli.bluetooth.interfaces.bluetooth.RcspCommandCallback
import com.jielihome.jielihome.bridge.EventDispatcher
import com.jielihome.jielihome.feature.ConnectFeature
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import java.io.File
import java.io.RandomAccessFile
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * OTA 升级。
 *
 * # 重要说明
 * **当前 SDK 包（jl_bluetooth_rcsp）只提供 OTA 协议的原始 Cmd，没有高层 OTA 管理器。**
 * 完整 OTA 流（含 CRC 校验、断点续传、双备份切换）通常在杰理另发的 `jl_otalib_*.aar`
 * 里实现。本实现是基于公开 cmd 的「最小可工作版」，**生产前需在真机验证**。
 *
 * # 状态机
 * IDLE → INQUIRING → NOTIFYING_SIZE → ENTERING → TRANSFERRING(progress) → VERIFYING
 *      → REBOOTING → DONE / FAILED / CANCELLED
 *
 * # 数据流（推测的协议，需真机验证）
 *   1. InquireUpdate(file flag)               → device 决定能否升级
 *   2. NotifyUpdateContentSize(totalSize)     → 告知固件包大小
 *   3. EnterUpdateMode                        → device 进入升级态
 *   4. Loop:
 *        GetUpdateFileOffset                  → device 告知它需要从哪个 offset 开始
 *        FirmwareUpdateBlock(offset, len)     → APP 发块（数据塞在响应里）
 *      until offset >= totalSize
 *   5. FirmwareUpdateStatus                   → device 验证结果
 *   6. ExitUpdateMode + RebootDevice
 *
 * # 调用方式
 *   server.otaFeature.start(address, "/sdcard/firmware.ufw")
 *   server.otaFeature.cancel()
 */
class OtaFeature(
    private val btManager: JL_BluetoothManager,
    private val connectFeature: ConnectFeature,
    private val dispatcher: EventDispatcher,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val running = AtomicBoolean(false)
    private var job: Job? = null

    fun isRunning(): Boolean = running.get()

    fun start(
        address: String? = null,
        firmwareFilePath: String,
        /** 块大小（设备可能在响应里给出建议值；这里只是默认） */
        blockSize: Int = 512,
        /** 升级文件标记（杰理协议要求；常见空数组或自定义校验） */
        fileFlagBytes: ByteArray = ByteArray(0),
    ) {
        if (!running.compareAndSet(false, true)) {
            emitError(-1, "ota already running"); return
        }
        val device = address?.let { connectFeature.deviceByAddress(it) }
            ?: connectFeature.connectedDevice()
        if (device == null) {
            emitError(-2, "no connected device")
            running.set(false); return
        }
        val file = File(firmwareFilePath)
        if (!file.isFile || file.length() <= 0) {
            emitError(-3, "firmware file invalid: $firmwareFilePath")
            running.set(false); return
        }
        emitState(State.INQUIRING, 0, file.length())
        job = scope.launch { runFlow(device, file, blockSize, fileFlagBytes) }
    }

    fun cancel() {
        job?.cancel()
        job = null
        running.set(false)
        emitState(State.CANCELLED, -1, 0)
    }

    // ───── 内部主流程 ─────

    private suspend fun runFlow(
        device: BluetoothDevice,
        file: File,
        blockSize: Int,
        fileFlagBytes: ByteArray,
    ) {
        try {
            val totalSize = file.length()

            // 1. Inquire
            val inquire: InquireUpdateResponse = sendCmd(
                device, InquireUpdateCmd(InquireUpdateParam(fileFlagBytes))
            )
            if (inquire.canUpdateFlag != 0) {
                throw IllegalStateException("device refused update, flag=${inquire.canUpdateFlag}")
            }

            // 2. NotifyContentSize
            emitState(State.NOTIFYING_SIZE, 0, totalSize)
            sendCmd<com.jieli.bluetooth.bean.base.CommonResponse>(
                device,
                NotifyUpdateContentSizeCmd(NotifyUpdateContentSizeParam(totalSize.toInt()))
            )

            // 3. Enter update mode
            emitState(State.ENTERING, 0, totalSize)
            val enter: EnterUpdateModeResponse = sendCmd(device, EnterUpdateModeCmd())
            if (enter.canUpdateFlag != 0) {
                throw IllegalStateException("enter update mode failed, flag=${enter.canUpdateFlag}")
            }

            // 4. Block transfer loop
            emitState(State.TRANSFERRING, 0, totalSize)
            RandomAccessFile(file, "r").use { raf ->
                var safety = 0
                while (running.get()) {
                    val ofs: UpdateFileOffsetResponse = sendCmd(device, GetUpdateFileOffsetCmd())
                    val nextOffset = ofs.updateFileFlagOffset.toLong()
                    val askLen = ofs.updateFileFlagLen.takeIf { it > 0 } ?: blockSize
                    if (nextOffset >= totalSize) break

                    val len = minOf(askLen.toLong(), totalSize - nextOffset).toInt()
                    val data = ByteArray(len)
                    raf.seek(nextOffset)
                    raf.readFully(data)

                    val blockCmd = FirmwareUpdateBlockCmd(
                        FirmwareUpdateBlockParam(nextOffset.toInt(), len)
                    )
                    // 在响应里塞数据：杰理协议要求 APP 把块数据放在 response 里，
                    // 而不是 param 里（FirmwareUpdateBlockParam 没有 data 字段）。
                    // 这里我们走 sendRcspResponse 模式：先把 cmd 当作"已收到的 device 请求"
                    // 处理，然后回响应。需要 SDK 内部支持；如果直接 sendRcspCommand 不行，
                    // 真机调试时切到 device-initiated 流（见类注释）。
                    val resp = FirmwareUpdateBlockResponse().setFirmwareUpdateBlockData(data)
                    blockCmd.response = resp
                    sendBlock(device, blockCmd)

                    val written = nextOffset + len
                    emitState(State.TRANSFERRING, written, totalSize)
                    safety++
                    if (safety > 200_000) throw IllegalStateException("too many block iterations")
                    delay(0L) // yield
                }
                if (!running.get()) throw CancellationException()
            }

            // 5. Verify
            emitState(State.VERIFYING, totalSize, totalSize)
            val status: FirmwareUpdateStatusResponse = sendCmd(device, FirmwareUpdateStatusCmd())
            if (status.result != 0) throw IllegalStateException("verify failed result=${status.result}")

            // 6. Exit + Reboot
            emitState(State.REBOOTING, totalSize, totalSize)
            runCatching { sendCmd<com.jieli.bluetooth.bean.response.ExitUpdateModeResponse>(device, ExitUpdateModeCmd()) }
            runCatching { sendCmd<com.jieli.bluetooth.bean.response.RebootDeviceResponse>(device, RebootDeviceCmd(RebootDeviceParam(0))) }

            emitState(State.DONE, totalSize, totalSize)
        } catch (ce: CancellationException) {
            emitState(State.CANCELLED, -1, file.length())
        } catch (t: Throwable) {
            emitError(-100, "ota failed: ${t.message}")
            emitState(State.FAILED, -1, file.length())
        } finally {
            running.set(false)
        }
    }

    /** 普通 OTA 控制命令：APP 发，等设备响应 */
    private suspend inline fun <reified R> sendCmd(
        device: BluetoothDevice,
        cmd: CommandBase<*, *>,
    ): R = suspendCancellableCoroutine { cont ->
        btManager.sendRcspCommand(device, cmd, object : RcspCommandCallback {
            override fun onCommandResponse(d: BluetoothDevice?, resp: CommandBase<*, *>?) {
                @Suppress("UNCHECKED_CAST")
                val r = resp?.response as? R
                if (r != null) cont.resume(r)
                else cont.resumeWithException(IllegalStateException("unexpected response"))
            }

            override fun onErrCode(d: BluetoothDevice?, err: BaseError?) {
                cont.resumeWithException(IllegalStateException("err ${err?.code}: ${err?.message}"))
            }
        })
    }

    /** 块响应：把已经填好 response 的 cmd 通过 sendRcspResponse 回设备 */
    private suspend fun sendBlock(
        device: BluetoothDevice,
        cmd: FirmwareUpdateBlockCmd,
    ) = suspendCancellableCoroutine<Unit> { cont ->
        try {
            // 先尝试 sendRcspResponse（device-initiated 模式）
            btManager.sendRcspResponse(device, cmd)
            cont.resume(Unit)
        } catch (t: Throwable) {
            // 兜底：sendRcspCommand
            btManager.sendRcspCommand(device, cmd, object : RcspCommandCallback {
                override fun onCommandResponse(d: BluetoothDevice?, resp: CommandBase<*, *>?) { cont.resume(Unit) }
                override fun onErrCode(d: BluetoothDevice?, err: BaseError?) {
                    cont.resumeWithException(IllegalStateException("block err ${err?.code}: ${err?.message}"))
                }
            })
        }
    }

    // ───── 事件 ─────

    enum class State { IDLE, INQUIRING, NOTIFYING_SIZE, ENTERING, TRANSFERRING, VERIFYING, REBOOTING, DONE, FAILED, CANCELLED }

    private fun emitState(state: State, sent: Long, total: Long) {
        val percent = if (total > 0 && sent in 0..total) (sent * 100.0 / total).toInt() else -1
        dispatcher.send(
            mapOf(
                "type" to "otaState",
                "state" to state.name,
                "sent" to sent,
                "total" to total,
                "percent" to percent,
                "tsMs" to System.currentTimeMillis(),
            )
        )
    }

    private fun emitError(code: Int, msg: String?) {
        dispatcher.send(
            mapOf("type" to "otaError", "code" to code, "message" to msg)
        )
    }
}
