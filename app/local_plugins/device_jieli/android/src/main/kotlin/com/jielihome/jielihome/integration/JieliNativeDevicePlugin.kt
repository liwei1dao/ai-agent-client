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
            emit(DevicePluginEvent(
                type = DevicePluginEventType.DEVICE_DISCOVERED,
                discovered = DiscoveredDevice(
                    id = (payload["address"] as? String) ?: "",
                    name = (payload["name"] as? String) ?: "",
                    rssi = (payload["rssi"] as? Number)?.toInt(),
                    vendor = VENDOR_KEY,
                    metadata = mapOf(
                        "edrAddr" to payload["edrAddr"],
                        "deviceType" to payload["deviceType"],
                        "connectWay" to payload["connectWay"],
                    ),
                ),
            ))
        }

        override fun onConnectionState(address: String, state: Int) {
            val session = _activeSession ?: return
            if (session.deviceId != address) return
            when (state) {
                2 -> session.setState(DeviceConnectionState.CONNECTING)
                1 -> session.setState(DeviceConnectionState.LINK_CONNECTED)
                0 -> {
                    session.setState(DeviceConnectionState.DISCONNECTED)
                    _activeSession = null
                    val pending = _pendingConnect
                    if (pending != null && !pending.isDone) {
                        pending.completeExceptionally(
                            DeviceException(
                                DeviceErrorCode.DISCONNECTED_REMOTE,
                                "disconnected before ready",
                            )
                        )
                        _pendingConnect = null
                        _pendingConnectAddress = null
                    }
                }
            }
        }

        override fun onRcspInit(address: String, code: Int) {
            val session = _activeSession ?: return
            if (session.deviceId != address) return
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
        server.scanFeature.startScan(ms).onFailure {
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
        )
        _activeSession = session

        val future = CompletableFuture<NativeDeviceSession>()
        _pendingConnect = future
        _pendingConnectAddress = deviceId

        server.connectFeature.connect(
            bleAddress = deviceId,
            edrAddress = extra["edrAddr"] as? String,
            deviceType = (extra["deviceType"] as? Number)?.toInt() ?: 0,
            connectWay = (extra["connectWay"] as? Number)?.toInt() ?: 0,
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
