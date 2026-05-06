package com.jielihome.jielihome.feature

import android.annotation.SuppressLint
import android.bluetooth.BluetoothManager
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.util.Log
import com.jieli.bluetooth.bean.BluetoothOption
import com.jieli.bluetooth.utils.ParseDataUtil
import com.jielihome.jielihome.bridge.EventDispatcher
import java.util.UUID

/**
 * BLE 扫描入口。
 *
 * 不再走 Jieli SDK 的 `btManager.scan()`（受其内置 ParseDataUtil 的
 * flagContent / strategy 限制），改为直接用 Android 原生
 * [BluetoothLeScanner] + [ScanFilter] 扫描，复合过滤：
 *
 * - [nameList]：对 `BluetoothDevice.name` 精确匹配（忽略大小写），空 = 不按名过滤
 * - [uuidList]：构造 `ScanFilter.setServiceUuid(...)`，由 OS 过滤；空 = 不按 UUID 过滤
 *
 * 两者同时设置时按 (UUID 由 OS 过滤后) AND (名字命中) 上报。
 *
 * 由于不再依赖 Jieli SDK 的 `BleScanMessage`，发出的 `deviceFound` 事件里
 * `edrAddr` / `deviceType` / `connectWay` 三个字段为 null —— 后续连接由
 * [com.jielihome.jielihome.feature.ConnectFeature] 用默认值（deviceType=-1,
 * connectWay=0）尝试，可在调用方通过 connectWay override 指定。
 */
class ScanFeature(
    private val context: Context,
    private val dispatcher: EventDispatcher,
) {

    private val mainHandler = Handler(Looper.getMainLooper())

    /**
     * 用于把 Android 原生 ScanRecord 字节交给 Jieli SDK 解析的可复用 option。
     * `bleScanStrategy=3` + 空 flagContent → 跳过 SDK 的 flagContent.equals 校验，
     * 任何 mode-3 可解析的 Jieli 广播都返回 BleScanMessage（含 edrAddr/pid 等）。
     */
    private val parserOption: BluetoothOption by lazy {
        BluetoothOption.createDefaultOption().apply {
            setBleScanStrategy(3)
            setScanFilterData("")
        }
    }

    @Volatile private var scanCallback: ScanCallback? = null
    @Volatile private var scanning: Boolean = false
    private var stopRunnable: Runnable? = null

    @Volatile private var currentNameList: List<String> = emptyList()
    @Volatile private var currentSkipUnnamed: Boolean = true

    @SuppressLint("MissingPermission")
    fun startScan(
        timeoutMs: Int,
        nameList: List<String> = emptyList(),
        uuidList: List<String> = emptyList(),
        skipUnnamed: Boolean = true,
    ): Result<Unit> {
        val scanner = leScanner()
            ?: return Result.failure(IllegalStateException("BLE scanner unavailable"))

        // 已在扫描：先停旧的（替换扫描参数）
        if (scanning) doStop(scanner)

        currentNameList = nameList.filter { it.isNotEmpty() }
        currentSkipUnnamed = skipUnnamed

        val filters = mutableListOf<ScanFilter>()
        uuidList.forEach { raw ->
            val uuid = parseUuid(raw) ?: return@forEach
            filters.add(
                ScanFilter.Builder()
                    .setServiceUuid(ParcelUuid(uuid))
                    .build()
            )
            Log.d(TAG, "add ScanFilter serviceUuid=$uuid")
        }

        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
            .setReportDelay(0)
            .build()

        val cb = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                handleScanResult(result)
            }

            override fun onBatchScanResults(results: MutableList<ScanResult>) {
                for (r in results) handleScanResult(r)
            }

            override fun onScanFailed(errorCode: Int) {
                Log.e(TAG, "onScanFailed errorCode=$errorCode")
                scanning = false
                scanCallback = null
                stopRunnable?.let { mainHandler.removeCallbacks(it) }
                stopRunnable = null
                dispatcher.send(
                    mapOf("type" to "scanStatus", "ble" to true, "started" to false)
                )
            }
        }

        return try {
            // filters 为空时传 null（"扫描所有 BLE 广播"）
            scanner.startScan(filters.takeIf { it.isNotEmpty() }, settings, cb)
            scanCallback = cb
            scanning = true
            Log.d(
                TAG,
                "startScan timeoutMs=$timeoutMs filters=${filters.size} " +
                        "nameList=$currentNameList"
            )
            dispatcher.send(
                mapOf("type" to "scanStatus", "ble" to true, "started" to true)
            )

            val stop = Runnable {
                Log.d(TAG, "scan timeout reached, stopping")
                stopScan()
            }
            stopRunnable = stop
            mainHandler.postDelayed(stop, timeoutMs.toLong())

            Result.success(Unit)
        } catch (e: Exception) {
            Log.e(TAG, "startScan exception", e)
            scanning = false
            Result.failure(e)
        }
    }

    fun stopScan() {
        val scanner = leScanner() ?: return
        doStop(scanner)
    }

    @SuppressLint("MissingPermission")
    private fun doStop(scanner: BluetoothLeScanner) {
        val cb = scanCallback
        if (cb != null) {
            try {
                scanner.stopScan(cb)
            } catch (e: Exception) {
                Log.w(TAG, "stopScan exception: ${e.message}")
            }
        }
        scanCallback = null
        stopRunnable?.let { mainHandler.removeCallbacks(it) }
        stopRunnable = null
        scanning = false
        currentNameList = emptyList()
        dispatcher.send(
            mapOf("type" to "scanStatus", "ble" to true, "started" to false)
        )
    }

    fun isScanning(): Boolean = scanning

    @SuppressLint("MissingPermission")
    private fun handleScanResult(result: ScanResult) {
        val device = result.device
        val name = try {
            device.name ?: result.scanRecord?.deviceName
        } catch (_: SecurityException) { null }

        // 未命名过滤（默认 ON）：drop 掉 name 为空的环境噪声
        if (currentSkipUnnamed && name.isNullOrEmpty()) return

        val names = currentNameList
        if (names.isNotEmpty()) {
            if (name.isNullOrEmpty() ||
                names.none { it.equals(name, ignoreCase = true) }
            ) return
        }

        // 用 Jieli SDK 的 ParseDataUtil 解一次原始 ScanRecord，能解出来就拿到
        // edrAddr / pid / deviceType / connectWay 等私有字段；解不出来就当作普通
        // BLE 设备（这些字段为 null，连接时走 BLE-only fallback）。
        val rawBytes = result.scanRecord?.bytes
        val msg = if (rawBytes != null) {
            try { ParseDataUtil.isFilterBleDevice(parserOption, rawBytes) }
            catch (e: Throwable) {
                Log.w(TAG, "parseBleScanMessage failed: ${e.message}")
                null
            }
        } else null

        Log.d(
            TAG,
            "result name=${name ?: "<null>"} addr=${device.address} rssi=${result.rssi} " +
                    "jieli=${msg != null} edr=${msg?.edrAddr ?: "-"} " +
                    "pid=${msg?.pid ?: "-"} dt=${msg?.deviceType ?: "-"} cw=${msg?.connectWay ?: "-"}"
        )

        dispatcher.send(
            mapOf(
                "type" to "deviceFound",
                "name" to (name ?: ""),
                "address" to device.address,
                "edrAddr" to msg?.edrAddr,
                "deviceType" to msg?.deviceType,
                "connectWay" to msg?.connectWay,
                "rssi" to result.rssi
            )
        )
    }

    private fun leScanner(): BluetoothLeScanner? {
        val mgr = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            ?: return null
        return mgr.adapter?.bluetoothLeScanner
    }

    private fun parseUuid(raw: String): UUID? {
        val s = raw.trim()
        return try {
            when {
                s.length == 4 -> UUID.fromString("0000$s-0000-1000-8000-00805f9b34fb")
                s.length == 8 -> UUID.fromString("$s-0000-1000-8000-00805f9b34fb")
                s.length == 36 -> UUID.fromString(s)
                s.length == 32 -> UUID.fromString(
                    "${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}" +
                            "-${s.substring(16, 20)}-${s.substring(20, 32)}"
                )
                else -> {
                    Log.w(TAG, "invalid UUID format: $raw")
                    null
                }
            }
        } catch (e: IllegalArgumentException) {
            Log.e(TAG, "parseUuid failed: $raw", e)
            null
        }
    }

    private companion object {
        const val TAG = "JieliScan"
    }
}
