package com.aiagent.device_manager

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.Context
import android.util.Log
import com.aiagent.device_plugin_interface.*
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.withContext
import kotlin.coroutines.coroutineContext
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * device_manager Flutter plugin —— Method/Event channel 入口。
 *
 *  - method channel `device_manager/method`：
 *      listVendors / useVendor / clearVendor / activeVendor / activeSession /
 *      startScan / stopScan / bondedDevices /
 *      connect / disconnect /
 *      readBattery / refreshInfo / invokeFeature
 *  - event channel `device_manager/events`：聚合事件（vendor / scan / session ...）
 *  - event channel `device_manager/triggers`：设备唤醒触发流（PTT / 翻译键 / 挂断）
 *
 * 编排逻辑全部在 [DefaultNativeDeviceManager]。
 */
class DeviceManagerPlugin : FlutterPlugin {

    companion object {
        private const val TAG = "DeviceManagerPlugin"
    }

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var triggerChannel: EventChannel
    private lateinit var otaChannel: EventChannel

    private val mainScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val ioScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var eventJob: Job? = null
    private var triggerJob: Job? = null
    private var otaJob: Job? = null
    private var appContext: Context? = null

    /**
     * OTA 进度总线 —— `download → port` 两阶段事件统一从这里出。
     *
     * 容器层下载 Url 固件时本地派 [DeviceOtaState.DOWNLOADING] 帧；下载完成转
     * file 请求后，会把厂商 [DeviceOtaPort.progressStream] forward 到本总线，
     * 让 Flutter 端只订阅一条流就能看到完整 OTA 生命周期。
     *
     * `replay = 1`：保证用户后开 OTA 页面也能立即看到最新一帧。
     */
    private val otaBus = MutableSharedFlow<Map<String, Any?>>(
        replay = 1,
        extraBufferCapacity = 64,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )
    private var otaDownloadJob: Job? = null
    private var otaForwardJob: Job? = null
    @Volatile private var otaTempFile: File? = null
    @Volatile private var otaInFlight: Boolean = false

    private val manager: DefaultNativeDeviceManager by lazy {
        DefaultNativeDeviceManager.get().also { it.initialize() }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        // event channel
        eventChannel = EventChannel(binding.binaryMessenger, "device_manager/events")
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventJob?.cancel()
                eventJob = mainScope.launch {
                    manager.eventStream.collect { evt ->
                        runCatching { events?.success(toMap(evt)) }
                    }
                }
            }
            override fun onCancel(arguments: Any?) {
                eventJob?.cancel()
                eventJob = null
            }
        })

        // OTA progress 走专属 channel：进度刷新频率高（每帧 1KB×N，约 5-20Hz），
        // 混入通用 events 流会拖累其它订阅者。下载与传输两阶段都从 [otaBus] 出，
        // 客户端订阅一次即可拿到完整生命周期。
        otaChannel = EventChannel(binding.binaryMessenger, "device_manager/ota")
        otaChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                otaJob?.cancel()
                otaJob = mainScope.launch {
                    otaBus.asSharedFlow().collect { p ->
                        runCatching { events?.success(p) }
                    }
                }
            }
            override fun onCancel(arguments: Any?) {
                otaJob?.cancel()
                otaJob = null
            }
        })

        triggerChannel = EventChannel(binding.binaryMessenger, "device_manager/triggers")
        triggerChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                triggerJob?.cancel()
                triggerJob = mainScope.launch {
                    manager.agentTriggers.collect { t ->
                        runCatching {
                            events?.success(mapOf(
                                "deviceId" to t.deviceId,
                                "kind" to t.kind.name.lowercase(),
                                "payload" to t.payload,
                            ))
                        }
                    }
                }
            }
            override fun onCancel(arguments: Any?) {
                triggerJob?.cancel()
                triggerJob = null
            }
        })

        // method channel
        methodChannel = MethodChannel(binding.binaryMessenger, "device_manager/method")
        methodChannel.setMethodCallHandler { call, result ->
            // 阻塞型方法（connect / refreshInfo / invokeFeature / 等）必须从 main 移走，
            // 否则 native listener 在 SDK 线程派事件，但 main 阻塞等 future.get(...) → 死锁。
            // 简单起见统一派到 IO，本就轻量的同步查询（activeVendor / activeSession 等）
            // 也分担到 IO，单线程 dispatcher 排序，开销可忽略。
            mainScope.launch {
                try {
                    val ret = withContext(Dispatchers.IO) { invokeNative(call) }
                    result.success(ret)
                } catch (e: DeviceException) {
                    Log.w(TAG, "method ${call.method} → DeviceException: ${e.code} ${e.message}")
                    result.error(e.code, e.message, null)
                } catch (e: NotImplementedError) {
                    result.notImplemented()
                } catch (e: IllegalArgumentException) {
                    result.error("InvalidArgument", e.message, null)
                } catch (e: Exception) {
                    Log.e(TAG, "method ${call.method} failed", e)
                    result.error("DeviceManagerError",
                        e.message ?: e::class.java.simpleName, null)
                }
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        eventChannel.setStreamHandler(null)
        triggerChannel.setStreamHandler(null)
        otaChannel.setStreamHandler(null)
        methodChannel.setMethodCallHandler(null)
        eventJob?.cancel()
        triggerJob?.cancel()
        otaJob?.cancel()
        otaDownloadJob?.cancel()
        otaForwardJob?.cancel()
        cleanupTemp()
        ioScope.cancel()
        mainScope.cancel()
    }

    /**
     * 同步执行 native 调用（在 IO 线程跑），返回值直接作为 method channel result。
     * 抛 [DeviceException] / [IllegalArgumentException] / [NotImplementedError] 由
     * 上层 try/catch 转 result.error / result.notImplemented。
     */
    private fun invokeNative(call: MethodCall): Any? {
        return when (call.method) {
            "listVendors" -> manager.listVendors().map { it.toMap() }

            "useVendor" -> {
                val vendor = call.argument<String>("vendor")
                    ?: throw IllegalArgumentException("vendor required")
                val cfg = DevicePluginConfig.fromMap(
                    call.argument<Map<*, *>>("config")
                )
                manager.useVendor(vendor, cfg)
                null
            }

            "clearVendor" -> { manager.clearVendor(); null }

            "activeVendor" -> manager.activeVendor

            "activeCapabilities" -> manager.activeCapabilities.map { it.name }

            "activeSession" -> {
                val s = manager.activeSession ?: return null
                mapOf(
                    "deviceId" to s.deviceId,
                    "vendor" to s.vendor,
                    "state" to s.state.name,
                    "info" to s.info.toMap(),
                    "capabilities" to s.capabilities.map { it.name },
                )
            }

            "startScan" -> {
                val filter = DeviceScanFilter.fromMap(
                    call.argument<Map<*, *>>("filter")
                )
                val timeoutMs = call.argument<Number?>("timeoutMs")?.toLong()
                manager.startScan(filter, timeoutMs)
                null
            }

            "stopScan" -> { manager.stopScan(); null }

            "isBluetoothEnabled" -> {
                val mgr = appContext?.getSystemService(Context.BLUETOOTH_SERVICE)
                    as? BluetoothManager
                val adapter = mgr?.adapter ?: BluetoothAdapter.getDefaultAdapter()
                runCatching { adapter?.isEnabled }.getOrNull() ?: false
            }

            "bondedDevices" -> runCatching { manager.bondedDevices() }
                .getOrDefault(emptyList()).map { it.toMap() }

            "connect" -> {
                val deviceId = call.argument<String>("deviceId")
                    ?: throw IllegalArgumentException("deviceId required")
                val opts = DeviceConnectOptions.fromMap(
                    call.argument<Map<*, *>>("options")
                )
                val session = manager.connect(deviceId, opts)
                mapOf(
                    "deviceId" to session.deviceId,
                    "vendor" to session.vendor,
                    "state" to session.state.name,
                    "info" to session.info.toMap(),
                )
            }

            "disconnect" -> { manager.disconnect(); null }

            "readBattery" -> {
                val s = manager.activeSession
                    ?: throw DeviceException(
                        DeviceErrorCode.NO_ACTIVE_SESSION, "no active session"
                    )
                s.readBattery()
            }

            "readRssi" -> {
                val s = manager.activeSession
                    ?: throw DeviceException(
                        DeviceErrorCode.NO_ACTIVE_SESSION, "no active session"
                    )
                s.readRssi()
            }

            "refreshInfo" -> {
                val s = manager.activeSession
                    ?: throw DeviceException(
                        DeviceErrorCode.NO_ACTIVE_SESSION, "no active session"
                    )
                s.refreshInfo().toMap()
            }

            "invokeFeature" -> {
                val s = manager.activeSession
                    ?: throw DeviceException(
                        DeviceErrorCode.NO_ACTIVE_SESSION, "no active session"
                    )
                val key = call.argument<String>("key")
                    ?: throw IllegalArgumentException("key required")
                val args = call.argument<Map<*, *>>("args")
                    ?.entries
                    ?.associate { it.key.toString() to it.value }
                    ?: emptyMap()
                s.invokeFeature(key, args)
            }

            // ─── OTA ──────────────────────────────────────────────────────
            "otaStart" -> {
                val req = DeviceOtaRequest.fromMap(
                    call.argument<Map<*, *>>("request")
                        ?: throw IllegalArgumentException("request map required")
                )
                startOta(req)
                null
            }

            "otaCancel" -> {
                cancelOta()
                null
            }

            "otaIsRunning" -> {
                otaInFlight ||
                    (manager.activeSession?.otaPort()?.isRunning ?: false)
            }

            "otaSupported" -> {
                val s = manager.activeSession ?: return false
                DeviceCapability.OTA in s.capabilities && s.otaPort() != null
            }

            else -> throw NotImplementedError(call.method)
        }
    }

    // ─── OTA 编排 ──────────────────────────────────────────────────────────

    private fun requireOtaPort(): DeviceOtaPort {
        val s = manager.activeSession
            ?: throw DeviceException(
                DeviceErrorCode.NO_ACTIVE_SESSION, "no active session"
            )
        return s.otaPort()
            ?: throw DeviceException(
                DeviceErrorCode.NOT_SUPPORTED,
                "vendor '${s.vendor}' does not support ota",
            )
    }

    /**
     * 容器层 OTA 入口。Url 请求由本层下载到沙盒后转 file 请求，再分派给厂商
     * port —— 厂商插件不需要、也不应该做 HTTP，下载逻辑统一在容器。
     *
     * 如果上一轮还在跑（download 或 port），抛 OTA_BUSY；用户先 cancel 才能新启。
     */
    @Synchronized
    private fun startOta(req: DeviceOtaRequest) {
        if (otaInFlight) {
            throw DeviceException(DeviceErrorCode.OTA_BUSY, "ota already running")
        }
        // 校验 vendor 端口存在（fail fast，避免下载完了才发现没设备）。
        requireOtaPort()
        otaInFlight = true
        when (req) {
            is DeviceOtaRequest.Url -> {
                otaDownloadJob = ioScope.launch {
                    runDownloadThenStart(req)
                }
            }
            else -> {
                runStartOnPort(req)
            }
        }
    }

    @Synchronized
    private fun cancelOta() {
        // 先取消下载（如果在）。job.cancel 会抛 CancellationException，
        // runDownloadThenStart 的 finally 会派一帧 CANCELLED + cleanup。
        otaDownloadJob?.cancel()
        otaDownloadJob = null
        // 再让 vendor port 自己 cancel；它会通过 progressStream 派 CANCELLED。
        runCatching { manager.activeSession?.otaPort()?.cancel() }
    }

    private suspend fun runDownloadThenStart(req: DeviceOtaRequest.Url) {
        val cacheRoot = appContext?.cacheDir
            ?: run {
                emitOta(DeviceOtaState.FAILED,
                    errorCode = DeviceErrorCode.OTA_FILE_INVALID,
                    errorMessage = "no cache dir")
                otaInFlight = false
                return
            }
        val dir = File(cacheRoot, "ota").also { if (!it.isDirectory) it.mkdirs() }
        val tmp = File(dir, "ota_${System.currentTimeMillis()}.bin")
        otaTempFile = tmp

        emitOta(DeviceOtaState.DOWNLOADING, sentBytes = 0, totalBytes = -1, percent = -1)
        try {
            val total = downloadTo(req.url, req.headers, tmp) { sent, t ->
                val pct = if (t > 0) ((sent * 100) / t).toInt() else -1
                emitOta(
                    DeviceOtaState.DOWNLOADING,
                    sentBytes = sent,
                    totalBytes = t,
                    percent = pct,
                )
            }
            if (!coroutineContext.isActive) {
                cleanupTemp()
                emitOta(DeviceOtaState.CANCELLED, sentBytes = -1, totalBytes = total)
                otaInFlight = false
                return
            }
            // 下载完成 → 转 File 请求；保留原 blockSize / timeoutMs。
            val fileReq = DeviceOtaRequest.File(
                filePath = tmp.absolutePath,
                blockSize = req.blockSize,
                timeoutMs = req.timeoutMs,
            )
            // 切回 main 启动 port —— 厂商 SDK 期望主线程入口。
            withContext(Dispatchers.Main) { runStartOnPort(fileReq) }
        } catch (ce: CancellationException) {
            cleanupTemp()
            emitOta(DeviceOtaState.CANCELLED, sentBytes = -1, totalBytes = 0)
            otaInFlight = false
            throw ce
        } catch (t: Throwable) {
            Log.w(TAG, "ota download failed", t)
            cleanupTemp()
            emitOta(
                DeviceOtaState.FAILED,
                sentBytes = -1, totalBytes = 0,
                errorCode = DeviceErrorCode.OTA_FILE_INVALID,
                errorMessage = "download failed: ${t.message}",
            )
            otaInFlight = false
        }
    }

    private fun runStartOnPort(req: DeviceOtaRequest) {
        val port = try {
            requireOtaPort()
        } catch (e: DeviceException) {
            emitOta(
                DeviceOtaState.FAILED,
                errorCode = e.code,
                errorMessage = e.message,
            )
            otaInFlight = false
            cleanupTemp()
            return
        }
        // forward port 进度到总线；终态时清理。
        otaForwardJob?.cancel()
        otaForwardJob = mainScope.launch {
            try {
                port.progressStream.collect { p ->
                    otaBus.tryEmit(p.toMap() + extraOtaFields())
                    if (p.isTerminal) {
                        otaInFlight = false
                        cleanupTemp()
                    }
                }
            } catch (_: CancellationException) {
                // 主动 cancel forward —— port 自己会通过 cancel() 派 CANCELLED。
            }
        }
        try {
            port.start(req)
        } catch (e: DeviceException) {
            emitOta(
                DeviceOtaState.FAILED,
                errorCode = e.code,
                errorMessage = e.message,
            )
            otaInFlight = false
            otaForwardJob?.cancel()
            cleanupTemp()
        }
    }

    private fun cleanupTemp() {
        otaTempFile?.let { runCatching { it.delete() } }
        otaTempFile = null
    }

    private fun extraOtaFields(): Map<String, Any?> {
        val s = manager.activeSession ?: return emptyMap()
        return mapOf("deviceId" to s.deviceId)
    }

    private fun emitOta(
        state: DeviceOtaState,
        sentBytes: Long = 0,
        totalBytes: Long = 0,
        percent: Int = -1,
        errorCode: String? = null,
        errorMessage: String? = null,
    ) {
        otaBus.tryEmit(
            DeviceOtaProgress(
                state = state,
                sentBytes = sentBytes,
                totalBytes = totalBytes,
                percent = percent,
                tsMs = System.currentTimeMillis(),
                errorCode = errorCode,
                errorMessage = errorMessage,
            ).toMap() + extraOtaFields()
        )
    }

    /**
     * HTTP 下载到指定文件，回调每写入一块就上报进度。HTTP 5xx / 网络异常抛出，
     * coroutine cancel 时主动停止读取。HttpURLConnection 没有可中断 read，
     * 这里靠 [Job.isActive] 判断每读一块后是否要主动跳出。
     */
    private fun downloadTo(
        url: String,
        headers: Map<String, String>,
        out: File,
        onProgress: (sent: Long, total: Long) -> Unit,
    ): Long {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 15_000
            readTimeout = 30_000
            instanceFollowRedirects = true
            headers.forEach { (k, v) -> setRequestProperty(k, v) }
        }
        try {
            val code = conn.responseCode
            if (code !in 200..299) {
                throw IllegalStateException("http $code")
            }
            val total = conn.contentLengthLong.takeIf { it > 0 } ?: -1L
            conn.inputStream.use { input ->
                out.outputStream().use { output ->
                    val buf = ByteArray(16 * 1024)
                    var sent = 0L
                    var lastReport = 0L
                    while (true) {
                        // 容许 cancel：每轮检查 isActive。
                        if (!ioScope.isActive) throw CancellationException("download cancelled")
                        val n = input.read(buf)
                        if (n <= 0) break
                        output.write(buf, 0, n)
                        sent += n
                        // 节流上报：每 ≥ 64KB 或 ≥ 200ms 一帧。
                        val now = System.currentTimeMillis()
                        if (sent - lastReport > 64 * 1024 || now % 200 < 16) {
                            onProgress(sent, total)
                            lastReport = sent
                        }
                    }
                    onProgress(sent, total)
                    return total.takeIf { it > 0 } ?: sent
                }
            }
        } finally {
            conn.disconnect()
        }
    }

    // ─── event payload mappers ──────────────────────────────────────────────

    private fun toMap(e: DeviceManagerEvent): Map<String, Any?> {
        val base = mutableMapOf<String, Any?>(
            "type" to e.type.name.lowercase(),
        )
        e.vendorKey?.let { base["vendorKey"] = it }
        e.bluetoothEnabled?.let { base["bluetoothEnabled"] = it }
        e.discovered?.let { base["discovered"] = it.toMap() }
        e.activeDeviceId?.let { base["activeDeviceId"] = it }
        e.errorCode?.let { base["errorCode"] = it }
        e.errorMessage?.let { base["errorMessage"] = it }
        e.sessionEvent?.let { base["sessionEvent"] = sessionEventToMap(it) }
        // sessionSnapshot 显式带 null：Dart 侧据此清空缓存（disconnect / clearVendor）。
        if (e.type == DeviceManagerEventType.SNAPSHOT_UPDATED ||
            e.type == DeviceManagerEventType.ACTIVE_SESSION_CHANGED ||
            e.type == DeviceManagerEventType.SESSION_EVENT ||
            e.type == DeviceManagerEventType.VENDOR_CHANGED) {
            base["sessionSnapshot"] = e.sessionSnapshot
        }
        return base
    }

    private fun sessionEventToMap(e: DeviceSessionEvent): Map<String, Any?> {
        val m = mutableMapOf<String, Any?>(
            "type" to e.type.name.lowercase(),
            "deviceId" to e.deviceId,
        )
        e.connectionState?.let { m["connectionState"] = it.name }
        e.deviceInfo?.let { m["deviceInfo"] = it.toMap() }
        e.feature?.let {
            m["feature"] = mapOf("key" to it.key, "data" to it.data)
        }
        e.rssi?.let { m["rssi"] = it }
        e.raw?.let { m["raw"] = it }
        e.errorCode?.let { m["errorCode"] = it }
        e.errorMessage?.let { m["errorMessage"] = it }
        return m
    }
}
