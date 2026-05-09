package com.aiagent.device_manager

import android.util.Log
import com.aiagent.device_plugin_interface.*
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.*

/**
 * `NativeDeviceManager` 默认实现：单设备 / 单 active vendor / 进程内单例。
 *
 * 实现策略：把现有 Dart `DefaultDeviceManager` 的编排逻辑 1:1 翻译为 Kotlin。
 * vendor 工厂从 [NativeDevicePluginRegistry] 拉取——其它模块（如 translate_server
 * 的 `DevicePortLocator`）也通过本单例读 [activeSession] 拿到当前 vendor 句柄。
 *
 * 多订阅安全：[eventStream] / [agentTriggers] 用 `MutableSharedFlow.replay=0`，
 * `extraBufferCapacity` 给一定缓冲应对 SDK 突发事件（DROP_OLDEST 防止 SDK 阻塞）。
 */
class DefaultNativeDeviceManager : NativeDeviceManager {

    companion object {
        private const val TAG = "DefaultNativeDevMgr"

        @Volatile
        private var instance: DefaultNativeDeviceManager? = null

        /** 进程内单例。Plugin/Service/translate_server 等都拿同一个引用。 */
        fun get(): DefaultNativeDeviceManager =
            instance ?: synchronized(this) {
                instance ?: DefaultNativeDeviceManager().also { instance = it }
            }
    }

    @Volatile private var _activePlugin: NativeDevicePlugin? = null
    @Volatile private var _activeVendor: String? = null
    @Volatile private var _initialized = false
    @Volatile private var _disposed = false
    @Volatile private var _switching = false

    private var pluginEventJob: Job? = null
    private var sessionEventJob: Job? = null

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val _eventCtrl = MutableSharedFlow<DeviceManagerEvent>(
        replay = 0,
        extraBufferCapacity = 64,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )
    private val _triggerCtrl = MutableSharedFlow<DeviceAgentTrigger>(
        replay = 0,
        extraBufferCapacity = 16,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )

    override val eventStream: Flow<DeviceManagerEvent> = _eventCtrl.asSharedFlow()
    override val agentTriggers: Flow<DeviceAgentTrigger> = _triggerCtrl.asSharedFlow()

    override val activeVendor: String? get() = _activeVendor
    override val activeCapabilities: Set<DeviceCapability>
        get() = _activePlugin?.capabilities ?: emptySet()
    override val activeSession: NativeDeviceSession? get() = _activePlugin?.activeSession

    override fun listVendors(): List<VendorDescriptor> =
        NativeDevicePluginRegistry.listVendors()

    override fun initialize() {
        checkAlive()
        if (_initialized) return
        _initialized = true
        emit(DeviceManagerEvent(type = DeviceManagerEventType.MANAGER_READY))
    }

    @Synchronized
    override fun useVendor(vendorKey: String, config: DevicePluginConfig) {
        checkAlive()
        if (_switching) {
            throw DeviceException(DeviceErrorCode.VENDOR_SWITCHING)
        }
        if (!NativeDevicePluginRegistry.isRegistered(vendorKey)) {
            throw DeviceException(
                DeviceErrorCode.NOT_SUPPORTED,
                "vendor \"$vendorKey\" not registered",
            )
        }
        // 同 vendor 重复 useVendor：no-op（避免无谓的 dispose/init 抖动）
        if (_activeVendor == vendorKey && _activePlugin != null) {
            return
        }
        _switching = true
        try {
            teardownActiveLocked()
            val plugin = NativeDevicePluginRegistry.create(vendorKey)
            plugin.initialize(config)
            _activePlugin = plugin
            _activeVendor = vendorKey
            // 订阅插件事件流；plugin.dispose 会关闭 flow，这里 collect 自然终止
            pluginEventJob = scope.launch {
                plugin.eventStream.collect { onPluginEvent(it) }
            }
            emit(DeviceManagerEvent(
                type = DeviceManagerEventType.VENDOR_CHANGED,
                vendorKey = vendorKey,
                sessionSnapshot = currentSnapshot(),
            ))
            emitSnapshot()
        } finally {
            _switching = false
        }
    }

    @Synchronized
    override fun clearVendor() {
        checkAlive()
        if (_activePlugin == null) return
        teardownActiveLocked()
        emit(DeviceManagerEvent(
            type = DeviceManagerEventType.VENDOR_CHANGED,
            vendorKey = null,
            sessionSnapshot = null,
        ))
        emitSnapshot()
    }

    override fun startScan(filter: DeviceScanFilter?, timeoutMs: Long?) {
        requirePlugin().startScan(filter, timeoutMs)
    }

    override fun stopScan() {
        _activePlugin?.stopScan()
    }

    override fun bondedDevices(): List<DiscoveredDevice> = requirePlugin().bondedDevices()

    @Synchronized
    override fun connect(deviceId: String, options: DeviceConnectOptions?): NativeDeviceSession {
        val plugin = requirePlugin()
        // 单设备模型：先断开旧 session
        plugin.activeSession?.let { old ->
            if (old.deviceId != deviceId) teardownSessionLocked(old)
        }
        val session = plugin.connect(deviceId, options)
        bindSession(session)
        emitSnapshot()
        emit(DeviceManagerEvent(
            type = DeviceManagerEventType.ACTIVE_SESSION_CHANGED,
            activeDeviceId = session.deviceId,
            sessionSnapshot = currentSnapshot(),
        ))
        return session
    }

    @Synchronized
    override fun disconnect() {
        val s = _activePlugin?.activeSession ?: return
        teardownSessionLocked(s)
    }

    /**
     * 让 active plugin 与底层 SDK 对账一次（兜底用）。流程：
     *
     *  1. 委托给 plugin 的 [NativeDevicePlugin.syncActiveFromSdk]，它就地修复
     *     plugin 的 active session（重建 / 标断开 / no-op）。
     *  2. 对照 sync 前后的 session 引用变化做容器侧补救：
     *     - 出现新 session（之前为空 / 不同 deviceId）→ 重新 [bindSession] +
     *       派 ACTIVE_SESSION_CHANGED；
     *     - session 消失（之前有，现在为空）→ 取消订阅 + 派 ACTIVE_SESSION_CHANGED(null)。
     *  3. 不论哪种情况都补一次 SNAPSHOT_UPDATED，保证 Dart 端拿到最新真相。
     *
     * 调用方：Dart facade 的 refresh()（进设备扫描页 / 应用回前台时使用）。
     */
    @Synchronized
    override fun syncActiveFromSdk() {
        checkAlive()
        val plugin = _activePlugin ?: return
        val before = plugin.activeSession
        runCatching { plugin.syncActiveFromSdk() }.onFailure {
            Log.w(TAG, "plugin.syncActiveFromSdk failed", it)
        }
        val after = plugin.activeSession
        if (before !== after) {
            // 旧的 session 流不需要再监听
            sessionEventJob?.cancel()
            sessionEventJob = null
            if (after != null) bindSession(after)
            emit(DeviceManagerEvent(
                type = DeviceManagerEventType.ACTIVE_SESSION_CHANGED,
                activeDeviceId = after?.deviceId,
                sessionSnapshot = currentSnapshot(),
            ))
        }
        emitSnapshot()
    }

    override fun dispose() {
        if (_disposed) return
        _disposed = true
        teardownActiveLocked()
        scope.cancel()
    }

    // ─── 内部 ───────────────────────────────────────────────────────────────

    private fun checkAlive() {
        if (_disposed) throw IllegalStateException("DeviceManager already disposed")
    }

    private fun requirePlugin(): NativeDevicePlugin {
        checkAlive()
        return _activePlugin ?: throw DeviceException(
            DeviceErrorCode.PLUGIN_NOT_INITIALIZED,
            "no active vendor; call useVendor() first",
        )
    }

    private fun teardownActiveLocked() {
        val old = _activePlugin
        if (old != null) {
            old.activeSession?.let { teardownSessionLocked(it) }
            runCatching { old.dispose() }
        }
        pluginEventJob?.cancel()
        pluginEventJob = null
        _activePlugin = null
        _activeVendor = null
    }

    private fun teardownSessionLocked(s: NativeDeviceSession) {
        sessionEventJob?.cancel()
        sessionEventJob = null
        runCatching { s.disconnect() }
        emitSnapshot()
        emit(DeviceManagerEvent(
            type = DeviceManagerEventType.ACTIVE_SESSION_CHANGED,
            activeDeviceId = null,
            sessionSnapshot = null,
        ))
    }

    private fun bindSession(s: NativeDeviceSession) {
        sessionEventJob?.cancel()
        sessionEventJob = scope.launch {
            s.eventStream.collect { evt ->
                val snap = currentSnapshot()
                // 诊断：把"snapshot 被推为 null"的瞬间记到 log，方便排查"已链接设备一闪而过"。
                if (snap == null) {
                    Log.w(TAG, "bindSession.collect: snapshot=null on ${evt.type} " +
                        "(session=${s.deviceId} state=${s.state}); will clear Dart cache")
                }
                emit(DeviceManagerEvent(
                    type = DeviceManagerEventType.SESSION_EVENT,
                    sessionEvent = evt,
                    sessionSnapshot = snap,
                ))
                emitSnapshot()
                if (evt.type == DeviceSessionEventType.CONNECTION_STATE_CHANGED &&
                    evt.connectionState == DeviceConnectionState.DISCONNECTED) {
                    emit(DeviceManagerEvent(
                        type = DeviceManagerEventType.ACTIVE_SESSION_CHANGED,
                        activeDeviceId = null,
                        sessionSnapshot = null,
                    ))
                }
            }
        }
    }

    /** 把当前 active session 序列化为 Dart 直接消费的 map；无 session 返回 null。 */
    fun currentSnapshot(): Map<String, Any?>? {
        val s = activeSession ?: return null
        return mapOf(
            "deviceId" to s.deviceId,
            "vendor" to s.vendor,
            "state" to s.state.name,
            "info" to s.info.toMap(),
            "capabilities" to s.capabilities.map { it.name },
        )
    }

    private fun emitSnapshot() {
        emit(DeviceManagerEvent(
            type = DeviceManagerEventType.SNAPSHOT_UPDATED,
            sessionSnapshot = currentSnapshot(),
        ))
    }

    private fun onPluginEvent(e: DevicePluginEvent) {
        when (e.type) {
            DevicePluginEventType.BLUETOOTH_STATE_CHANGED ->
                emit(DeviceManagerEvent(
                    type = DeviceManagerEventType.BLUETOOTH_STATE_CHANGED,
                    bluetoothEnabled = e.bluetoothEnabled,
                ))
            DevicePluginEventType.SCAN_STARTED ->
                emit(DeviceManagerEvent(type = DeviceManagerEventType.SCAN_STARTED))
            DevicePluginEventType.SCAN_STOPPED ->
                emit(DeviceManagerEvent(type = DeviceManagerEventType.SCAN_STOPPED))
            DevicePluginEventType.DEVICE_DISCOVERED ->
                emit(DeviceManagerEvent(
                    type = DeviceManagerEventType.DEVICE_DISCOVERED,
                    discovered = e.discovered,
                ))
            DevicePluginEventType.WAKE_TRIGGERED -> {
                e.wake?.let {
                    _triggerCtrl.tryEmit(DeviceAgentTrigger(
                        deviceId = it.deviceId,
                        kind = wakeToTriggerKind(it.reason),
                        payload = it.payload,
                    ))
                }
            }
            DevicePluginEventType.ERROR ->
                emit(DeviceManagerEvent(
                    type = DeviceManagerEventType.ERROR,
                    errorCode = e.errorCode,
                    errorMessage = e.errorMessage,
                ))
            else -> {
                // PLUGIN_READY / PLUGIN_DISPOSED / CONNECTION_STATE_CHANGED /
                // DEVICE_INFO_UPDATED / BOND_STATE_CHANGED / CUSTOM_EVENT —
                // 这些事件经 session 流（或不再向上聚合），此处不重复广播。
            }
        }
    }

    private fun emit(e: DeviceManagerEvent) {
        _eventCtrl.tryEmit(e)
    }

    private fun wakeToTriggerKind(r: WakeReason): DeviceAgentTrigger.Kind = when (r) {
        WakeReason.PTT, WakeReason.VOICE_WAKE -> DeviceAgentTrigger.Kind.CHAT
        WakeReason.TRANSLATE_KEY -> DeviceAgentTrigger.Kind.TRANSLATE
        WakeReason.HANGUP -> DeviceAgentTrigger.Kind.STOP
    }
}
