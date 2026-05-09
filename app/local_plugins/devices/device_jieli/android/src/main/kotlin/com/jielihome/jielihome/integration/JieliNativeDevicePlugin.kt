package com.jielihome.jielihome.integration

import android.content.Context
import android.util.Log
import com.aiagent.device_plugin_interface.DeviceCapability
import com.aiagent.device_plugin_interface.DeviceConnectOptions
import com.aiagent.device_plugin_interface.DeviceConnectionState
import com.aiagent.device_plugin_interface.DeviceErrorCode
import com.aiagent.device_plugin_interface.DeviceException
import com.aiagent.device_plugin_interface.DevicePluginConfig
import com.aiagent.device_plugin_interface.DevicePluginEvent
import com.aiagent.device_plugin_interface.DevicePluginEventType
import com.aiagent.device_plugin_interface.DeviceScanFilter
import com.aiagent.device_plugin_interface.DiscoveredDevice
import com.aiagent.device_plugin_interface.NativeDevicePlugin
import com.aiagent.device_plugin_interface.NativeDevicePluginRegistry
import com.aiagent.device_plugin_interface.NativeDeviceSession
import com.jielihome.jielihome.api.JieliEventAdapter
import com.jielihome.jielihome.api.JieliEventListener
import com.jielihome.jielihome.core.JieliHomeServer
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit

/**
 * 杰理 [NativeDevicePlugin] 实现 —— 把 [JieliHomeServer] 包成 vendor-agnostic 接口，
 * 由 device_manager native ([com.aiagent.device_manager.DefaultNativeDeviceManager])
 * 通过 [NativeDevicePluginRegistry] 创建并管理。
 *
 * 注册入口：[register]，由 `JielihomePlugin.onAttachedToEngine` 调用一次。
 *
 * 注意：本类**不**关闭 [JieliHomeServer] —— server 是进程级单例，可能被 Dart 直连
 * 路径 / translate_server / OTA 等并发使用，本类的 [dispose] 只解订阅事件 + 切断
 * 当前 session，server 自身保留。
 */
class JieliNativeDevicePlugin(
    private val context: Context,
) : NativeDevicePlugin {

    companion object {
        private const val TAG = "JieliNativeDevicePlugin"
        const val VENDOR_KEY = "jieli"
        const val DISPLAY_NAME = "JieLi (杰理)"

        val CAPABILITIES: Set<DeviceCapability> = setOf(
            DeviceCapability.SCAN,
            DeviceCapability.CONNECT,
            DeviceCapability.BOND,
            DeviceCapability.BATTERY,
            DeviceCapability.CUSTOM_COMMAND,
            DeviceCapability.WAKE_WORD,
            DeviceCapability.OTA,
            DeviceCapability.ON_DEVICE_CALL_TRANSLATION,
            DeviceCapability.ON_DEVICE_FACE_TO_FACE_TRANSLATION,
            DeviceCapability.ON_DEVICE_RECORDING_TRANSLATION,
        )

        /**
         * 把杰理工厂注册到 [NativeDevicePluginRegistry]，由 [JielihomePlugin]
         * 在 onAttachedToEngine 调一次（FlutterPlugin 生命周期保证它早于 device_manager
         * 的 listVendors / useVendor 调用）。
         */
        fun register(appContext: Context) {
            NativeDevicePluginRegistry.register(
                vendorKey = VENDOR_KEY,
                displayName = DISPLAY_NAME,
                capabilities = CAPABILITIES,
            ) { JieliNativeDevicePlugin(appContext) }
        }
    }

    override val vendorKey: String = VENDOR_KEY
    override val displayName: String = DISPLAY_NAME
    override val capabilities: Set<DeviceCapability> = CAPABILITIES

    private val server: JieliHomeServer = JieliHomeServer.get()

    @Volatile private var _initialized = false
    @Volatile private var _disposed = false

    @Volatile private var _activeSession: JieliNativeDeviceSession? = null
    @Volatile private var _pendingConnect: CompletableFuture<NativeDeviceSession>? = null
    @Volatile private var _pendingConnectAddress: String? = null

    private val _events = MutableSharedFlow<DevicePluginEvent>(
        replay = 0,
        extraBufferCapacity = 64,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )

    override val eventStream: Flow<DevicePluginEvent> = _events.asSharedFlow()

    private val listener: JieliEventListener = object : JieliEventAdapter() {
        override fun onAdapterStatus(enabled: Boolean, hasBle: Boolean) {
            emit(DevicePluginEvent(
                type = DevicePluginEventType.BLUETOOTH_STATE_CHANGED,
                bluetoothEnabled = enabled,
            ))
        }

        override fun onScanStatus(ble: Boolean, started: Boolean) {
            emit(DevicePluginEvent(
                type = if (started) DevicePluginEventType.SCAN_STARTED
                else DevicePluginEventType.SCAN_STOPPED,
            ))
        }

        override fun onDeviceFound(payload: Map<String, Any?>) {
            val meta = mutableMapOf<String, Any?>(
                "edrAddr" to payload["edrAddr"],
                "deviceType" to payload["deviceType"],
                "connectWay" to payload["connectWay"],
            )
            // 透传 ScanFeature 解析出的广播详情，供 UI 弹窗展示。
            listOf(
                "rawAdv",
                "advRecords",
                "advFlags",
                "manufacturerCompanyId",
                "manufacturerData",
                "serviceUuids",
            ).forEach { key ->
                if (payload.containsKey(key)) meta[key] = payload[key]
            }
            emit(DevicePluginEvent(
                type = DevicePluginEventType.DEVICE_DISCOVERED,
                discovered = DiscoveredDevice(
                    id = (payload["address"] as? String) ?: "",
                    name = (payload["name"] as? String) ?: "",
                    rssi = (payload["rssi"] as? Number)?.toInt(),
                    vendor = VENDOR_KEY,
                    metadata = meta,
                ),
            ))
        }

        override fun onConnectionState(address: String, state: Int) {
            val session = _activeSession ?: return
            if (session.deviceId != address) return
            Log.d(TAG, "onConnectionState addr=$address state=$state")
            // SDK 状态码（com.jieli.bluetooth.constant.StateCode）：
            //   0 CONNECTION_DISCONNECT   1 CONNECTION_OK         2 CONNECTION_FAILED
            //   3 CONNECTION_CONNECTING   4 CONNECTION_CONNECTED
            //
            // 注意：曾经把 2 误当 CONNECTING 用，连接成功后 SDK 一旦补发 FAILED→DISCONNECT，
            // UI 就会出现"已链接设备一闪而过"的现象。FAILED 必须按断开处理。
            when (state) {
                3 -> session.setState(DeviceConnectionState.CONNECTING)
                1, 4 -> {
                    // BLE/EDR 链路就绪，等 RCSP 初始化。READY 状态下（onRcspInit 已先到）
                    // 不要把状态回退到 LINK_CONNECTED。
                    if (session.state != DeviceConnectionState.READY) {
                        session.setState(DeviceConnectionState.LINK_CONNECTED)
                    }
                }
                0, 2 -> {
                    session.setState(DeviceConnectionState.DISCONNECTED)
                    _activeSession = null
                    val pending = _pendingConnect
                    if (pending != null && !pending.isDone) {
                        val code = if (state == 2)
                            DeviceErrorCode.CONNECT_FAILED
                        else
                            DeviceErrorCode.DISCONNECTED_REMOTE
                        val msg = if (state == 2)
                            "connection failed"
                        else
                            "disconnected before ready"
                        pending.completeExceptionally(DeviceException(code, msg))
                        _pendingConnect = null
                        _pendingConnectAddress = null
                    }
                }
            }
        }

        override fun onRcspInit(address: String, code: Int) {
            val session = _activeSession ?: return
            if (session.deviceId != address) return
            Log.d(TAG, "onRcspInit addr=$address code=$code")
            if (code == 0) {
                session.setState(DeviceConnectionState.READY)
                val pending = _pendingConnect
                if (pending != null && _pendingConnectAddress == address && !pending.isDone) {
                    pending.complete(session)
                    _pendingConnect = null
                    _pendingConnectAddress = null
                }
            } else {
                val pending = _pendingConnect
                if (pending != null && _pendingConnectAddress == address && !pending.isDone) {
                    pending.completeExceptionally(
                        DeviceException(
                            DeviceErrorCode.HANDSHAKE_FAILED,
                            "RCSP init failed code=$code",
                        )
                    )
                    _pendingConnect = null
                    _pendingConnectAddress = null
                }
            }
        }

        override fun onBattery(address: String?, level: Int?) {
            val session = _activeSession ?: return
            if (address != null && session.deviceId != address) return
            // 由 session 自己 refresh info 拉一次最新快照
            runCatching { session.refreshInfo() }
        }

        override fun onTwsBroadcast(payload: Map<String, Any?>) {
            // TWS 设备主动推左右耳 / 电仓电量变化（佩戴 / 取出 / 充电态）。
            // 真值已经在 JieliNativeDeviceSession.applySnapshot 里映射好——这里直接
            // refreshInfo 让它重新合并 [DeviceInfoFeature.snapshot] 的最新数据并
            // 派 deviceInfoUpdated 事件，UI 上的电量 chip 自动刷新。
            val address = payload["address"] as? String
            val session = _activeSession ?: return
            if (address != null && session.deviceId != address) return
            runCatching { session.refreshInfo() }
        }

        override fun onTranslationAudio(payload: Map<String, Any?>) {
            _activeSession?.emitFeature("jieli.translation.audio", payload)
        }

        override fun onTranslationResult(payload: Map<String, Any?>) {
            _activeSession?.emitFeature("jieli.translation.result", payload)
        }

        override fun onTranslationLog(payload: Map<String, Any?>) {
            _activeSession?.emitFeature("jieli.translation.log", payload)
        }

        override fun onTranslationError(payload: Map<String, Any?>) {
            _activeSession?.emitError(
                "device.feature_failed",
                "translation: ${payload["code"]} ${payload["message"] ?: ""}",
            )
        }

        override fun onDeviceRecordStart(payload: Map<String, Any?>) {
            _activeSession?.emitFeature("jieli.deviceRecord.start", payload)
        }

        override fun onDeviceRecordAudio(payload: Map<String, Any?>) {
            _activeSession?.emitFeature("jieli.deviceRecord.audio", payload)
        }

        override fun onDeviceRecordStop(payload: Map<String, Any?>) {
            _activeSession?.emitFeature("jieli.deviceRecord.stop", payload)
        }

        override fun onDeviceRecordError(payload: Map<String, Any?>) {
            _activeSession?.emitError(
                "device.feature_failed",
                "deviceRecord: ${payload["code"]} ${payload["message"] ?: ""}",
            )
        }
    }

    // ─── NativeDevicePlugin 接口 ──────────────────────────────────────────

    override fun initialize(config: DevicePluginConfig) {
        checkAlive()
        if (_initialized) return
        if (!server.initialized) {
            server.initialize(
                context = context,
                multiDevice = (config.extra["multiDevice"] as? Boolean) ?: false,
                skipNoNameDev = (config.extra["skipNoNameDev"] as? Boolean) ?: false,
                enableLog = (config.extra["enableLog"] as? Boolean) ?: false,
            )
        }
        server.addEventListener(listener)
        _initialized = true
        emit(DevicePluginEvent(type = DevicePluginEventType.PLUGIN_READY))
    }

    override fun startScan(filter: DeviceScanFilter?, timeoutMs: Long?) {
        requireInit()
        val ms = (timeoutMs ?: 30_000L).toInt()
        val nameList = filter?.nameList?.filter { it.isNotEmpty() }
            ?.takeIf { it.isNotEmpty() }
            ?: filter?.namePrefix?.takeIf { it.isNotEmpty() }?.let { listOf(it) }
            ?: emptyList()
        val uuidList = filter?.serviceUuids?.filter { it.isNotEmpty() } ?: emptyList()
        val skipUnnamed = filter?.skipUnnamed ?: true
        server.scanFeature.startScan(ms, nameList, uuidList, skipUnnamed).onFailure {
            throw DeviceException("device.scan_failed", it.message, it)
        }
    }

    override fun stopScan() {
        if (!_initialized) return
        server.scanFeature.stopScan()
    }

    override fun isScanning(): Boolean =
        _initialized && server.scanFeature.isScanning()

    override fun bondedDevices(): List<DiscoveredDevice> {
        // 杰理 SDK 没暴露公开的"已配对"接口；不混入系统经典蓝牙列表。
        return emptyList()
    }

    override fun connect(deviceId: String, options: DeviceConnectOptions?): NativeDeviceSession {
        requireInit()
        // 单设备：有旧 session 时先断
        _activeSession?.let { if (it.deviceId != deviceId) runCatching { it.disconnect() } }

        val extra = options?.extra ?: emptyMap()
        val session = JieliNativeDeviceSession(
            server = server,
            deviceId = deviceId,
            initialName = (extra["name"] as? String) ?: "",
            capabilities = capabilities,
            otaCacheDir = context.cacheDir,
        )
        _activeSession = session

        val future = CompletableFuture<NativeDeviceSession>()
        _pendingConnect = future
        _pendingConnectAddress = deviceId

        val edrAddress = extra["edrAddr"] as? String
        val deviceType = (extra["deviceType"] as? Number)?.toInt() ?: 0
        val connectWay = (extra["connectWay"] as? Number)?.toInt() ?: 0
        Log.d(TAG, "connect deviceId=$deviceId edr=$edrAddress dt=$deviceType cw=$connectWay")
        server.connectFeature.connect(
            bleAddress = deviceId,
            edrAddress = edrAddress,
            deviceType = deviceType,
            connectWay = connectWay,
        ).onFailure {
            future.completeExceptionally(
                DeviceException(DeviceErrorCode.CONNECT_FAILED, it.message, it)
            )
            _pendingConnect = null
            _pendingConnectAddress = null
        }

        val timeout = (options?.timeoutMs ?: 15_000L)
        return try {
            future.get(timeout, TimeUnit.MILLISECONDS)
        } catch (e: java.util.concurrent.TimeoutException) {
            _pendingConnect = null
            _pendingConnectAddress = null
            throw DeviceException(DeviceErrorCode.CONNECT_TIMEOUT,
                "connect timeout after ${timeout}ms")
        } catch (e: java.util.concurrent.ExecutionException) {
            throw e.cause ?: e
        }
    }

    override val activeSession: NativeDeviceSession?
        get() = _activeSession?.takeIf { it.state != DeviceConnectionState.DISCONNECTED }

    /**
     * 与杰理 SDK 当前连接状态对账，修复"SDK 还连着 / app 失忆"造成的扫描页死锁。
     *
     * 三种走向：
     *  - SDK 当前有连接的设备（[ConnectFeature.connectedDevice] 非空），但本插件
     *    无 active session 或 deviceId 不一致或已断开 → 把旧 session 标
     *    DISCONNECTED 后重建一个，状态直接置 READY（SDK 都说连着了，RCSP 必然
     *    已握手），再 refreshInfo 一次拉最新电量/固件。
     *  - SDK 当前有连接的设备且 [_activeSession] 已存在但状态不是 READY（被中间
     *    态卡住）→ 直接 setState(READY)，不重建。
     *  - SDK 当前无连接但 [_activeSession] 还活着 → 把它标 DISCONNECTED 并清空。
     *
     * 完全一致时 no-op，不派任何事件，避免 UI 抖动。
     */
    override fun syncActiveFromSdk() {
        if (!_initialized || _disposed) return
        val sdkDevice = runCatching { server.connectFeature.connectedDevice() }.getOrNull()
        val sdkAddr = sdkDevice?.address
        val current = _activeSession

        if (sdkAddr != null) {
            if (current != null && current.deviceId == sdkAddr &&
                current.state != DeviceConnectionState.DISCONNECTED) {
                if (current.state != DeviceConnectionState.READY) {
                    Log.i(TAG, "syncActiveFromSdk: bump $sdkAddr ${current.state} → READY")
                    current.setState(DeviceConnectionState.READY)
                }
                runCatching { current.refreshInfo() }
                return
            }
            // 旧 session 过期或地址不一致：标 disconnected 让 OTA 等端口收尾
            current?.takeIf { it.state != DeviceConnectionState.DISCONNECTED }
                ?.setState(DeviceConnectionState.DISCONNECTED)
            val snapshotName =
                server.deviceInfoFeature.snapshot(sdkAddr)?.get("name") as? String
            val initialName = snapshotName?.takeIf { it.isNotEmpty() }
                ?: runCatching { sdkDevice.name }.getOrNull() ?: ""
            val rebuilt = JieliNativeDeviceSession(
                server = server,
                deviceId = sdkAddr,
                initialName = initialName,
                capabilities = capabilities,
                otaCacheDir = context.cacheDir,
            )
            rebuilt.setState(DeviceConnectionState.READY)
            runCatching { rebuilt.refreshInfo() }
            _activeSession = rebuilt
            Log.i(TAG, "syncActiveFromSdk: rebuilt session for sdk-connected $sdkAddr")
            return
        }

        if (current != null && current.state != DeviceConnectionState.DISCONNECTED) {
            Log.i(TAG, "syncActiveFromSdk: clear stale session ${current.deviceId} " +
                "(sdk has no connection)")
            current.setState(DeviceConnectionState.DISCONNECTED)
            _activeSession = null
        }
    }

    override fun dispose() {
        if (_disposed) return
        _disposed = true
        runCatching { _activeSession?.disconnect() }
        runCatching { server.removeEventListener(listener) }
        _activeSession = null
        emit(DevicePluginEvent(type = DevicePluginEventType.PLUGIN_DISPOSED))
    }

    // ─── 内部 ──────────────────────────────────────────────────────────────

    private fun checkAlive() {
        if (_disposed) throw IllegalStateException("JieliNativeDevicePlugin disposed")
    }

    private fun requireInit() {
        checkAlive()
        if (!_initialized) throw DeviceException(DeviceErrorCode.PLUGIN_NOT_INITIALIZED)
    }

    private fun emit(e: DevicePluginEvent) {
        if (!_events.tryEmit(e)) Log.w(TAG, "event buffer full; dropped ${e.type}")
    }
}
