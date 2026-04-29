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
import kotlinx.coroutines.withContext

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

    private val mainScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var eventJob: Job? = null
    private var triggerJob: Job? = null
    private var appContext: Context? = null

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
        methodChannel.setMethodCallHandler(null)
        eventJob?.cancel()
        triggerJob?.cancel()
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

            else -> throw NotImplementedError(call.method)
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
