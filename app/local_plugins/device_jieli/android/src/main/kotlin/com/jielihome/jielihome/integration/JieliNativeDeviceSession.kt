package com.jielihome.jielihome.integration

import android.util.Log
import com.aiagent.device_plugin_interface.DeviceCallTranslationPort
import com.aiagent.device_plugin_interface.DeviceCapability
import com.aiagent.device_plugin_interface.DeviceConnectionState
import com.aiagent.device_plugin_interface.DeviceErrorCode
import com.aiagent.device_plugin_interface.DeviceException
import com.aiagent.device_plugin_interface.DeviceFeatureEvent
import com.aiagent.device_plugin_interface.DeviceInfo
import com.aiagent.device_plugin_interface.DeviceOtaPort
import com.aiagent.device_plugin_interface.DeviceSessionEvent
import com.aiagent.device_plugin_interface.DeviceSessionEventType
import com.aiagent.device_plugin_interface.NativeDeviceSession
import com.jielihome.jielihome.core.JieliHomeServer
import com.jielihome.jielihome.feature.translation.TranslationStreams
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import java.io.File

/**
 * 杰理 [NativeDeviceSession] 实现 —— 包装 [JieliHomeServer] 的连接快照与事件。
 *
 * 状态机由 [JieliNativeDevicePlugin] 在 RCSP 事件回调里推动：
 *   - ConnectionStateEvent.state == CONNECTING(2) → connecting
 *   - state == OK(1) + RcspInit 未到 → linkConnected
 *   - RcspInit(success=true) → ready
 *   - state == DISCONNECT(0) → disconnected
 */
class JieliNativeDeviceSession internal constructor(
    private val server: JieliHomeServer,
    override val deviceId: String,
    initialName: String,
    override val capabilities: Set<DeviceCapability>,
    private val otaCacheDir: File,
) : NativeDeviceSession {

    companion object {
        private const val TAG = "JieliNativeSession"
    }

    override val vendor: String = "jieli"

    @Volatile private var _state = DeviceConnectionState.CONNECTING
    @Volatile private var _info = DeviceInfo(
        id = deviceId, name = initialName, vendor = vendor,
    )
    @Volatile private var _disposed = false

    override val state: DeviceConnectionState get() = _state
    override val info: DeviceInfo get() = _info

    private val _events = MutableSharedFlow<DeviceSessionEvent>(
        replay = 0,
        extraBufferCapacity = 32,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )

    override val eventStream: Flow<DeviceSessionEvent> = _events.asSharedFlow()

    // ─── 由 plugin 在事件回调中调用 ─────────────────────────────────────────

    @Volatile private var _otaPort: JieliOtaPort? = null

    internal fun setState(s: DeviceConnectionState) {
        if (_state == s) return
        _state = s
        emit(DeviceSessionEvent(
            type = DeviceSessionEventType.CONNECTION_STATE_CHANGED,
            deviceId = deviceId,
            connectionState = s,
        ))
        if (s == DeviceConnectionState.DISCONNECTED) {
            _disposed = true
            // 端口随 session 收尾：补一帧 FAILED + 解订阅，UI 才能跳出 OTA 锁定。
            runCatching { _otaPort?.shutdown(DeviceErrorCode.DISCONNECTED_REMOTE) }
            _otaPort = null
        }
    }

    internal fun emitFeature(key: String, data: Map<String, Any?>) {
        emit(DeviceSessionEvent(
            type = DeviceSessionEventType.FEATURE,
            deviceId = deviceId,
            feature = DeviceFeatureEvent(key = key, data = data),
        ))
    }

    internal fun emitError(code: String, message: String?) {
        emit(DeviceSessionEvent(
            type = DeviceSessionEventType.ERROR,
            deviceId = deviceId,
            errorCode = code,
            errorMessage = message,
        ))
    }

    private fun emit(e: DeviceSessionEvent) {
        if (!_events.tryEmit(e)) {
            Log.w(TAG, "session event buffer full; dropped ${e.type}")
        }
    }

    private fun applySnapshot(snapshot: Map<String, Any?>) {
        _info = _info.copyWith(
            name = (snapshot["name"] as? String).takeIf { !it.isNullOrEmpty() }
                ?: _info.name,
            firmwareVersion = (snapshot["versionName"] as? String)
                ?: _info.firmwareVersion,
            batteryPercent = (snapshot["battery"] as? Number)?.toInt(),
            metadata = snapshot,
        )
        emit(DeviceSessionEvent(
            type = DeviceSessionEventType.DEVICE_INFO_UPDATED,
            deviceId = deviceId,
            deviceInfo = _info,
        ))
    }

    // ─── NativeDeviceSession 接口 ──────────────────────────────────────────

    override fun readRssi(): Int {
        requireReady()
        throw DeviceException(
            DeviceErrorCode.NOT_SUPPORTED,
            "jieli native bridge does not expose RSSI yet",
        )
    }

    override fun readBattery(): Int? {
        requireReady()
        return server.deviceInfoFeature.snapshot(deviceId)
            ?.get("battery") as? Int
    }

    override fun refreshInfo(): DeviceInfo {
        requireReady()
        val snap = server.deviceInfoFeature.snapshot(deviceId) ?: return _info
        applySnapshot(snap)
        return _info
    }

    override fun invokeFeature(
        featureKey: String,
        args: Map<String, Any?>,
    ): Map<String, Any?> {
        requireReady()
        return when (featureKey) {
            "jieli.translation.support" -> mapOf(
                "supportCallStereo" to server.translationFeature
                    .isSupportCallTranslationWithStereo(deviceId),
            )

            "jieli.translation.start" -> {
                val modeId = (args["modeId"] as? Number)?.toInt()
                    ?: throw DeviceException(
                        DeviceErrorCode.INVALID_ARGUMENT,
                        "modeId(int) required",
                    )
                @Suppress("UNCHECKED_CAST")
                val extra = (args["args"] as? Map<String, Any?>) ?: emptyMap()
                server.translationFeature.start(modeId, extra).getOrElse {
                    throw DeviceException(
                        "device.feature_failed",
                        "translation.start failed: ${it.message}",
                        it,
                    )
                }
                mapOf("ok" to true)
            }

            "jieli.translation.stop" -> {
                server.translationFeature.stop()
                mapOf("ok" to true)
            }

            "jieli.translation.feedTranslatedAudio" -> {
                val pcm = args["pcm"] as? ByteArray
                    ?: (args["pcm"] as? List<*>)
                        ?.let { it.map { v -> (v as Number).toByte() }.toByteArray() }
                    ?: throw DeviceException(
                        DeviceErrorCode.INVALID_ARGUMENT,
                        "pcm(ByteArray|List<int>) required",
                    )
                val streamId = args["streamId"] as? String
                    ?: throw DeviceException(
                        DeviceErrorCode.INVALID_ARGUMENT,
                        "streamId required (e.g. ${TranslationStreams.OUT_UPLINK})",
                    )
                val ok = server.translationFeature.feedTranslatedAudio(
                    outputStreamId = streamId,
                    pcm = pcm,
                    format = com.jielihome.jielihome.feature.translation.AudioFormat(
                        sampleRate = (args["sampleRate"] as? Number)?.toInt() ?: 16000,
                        channels = (args["channels"] as? Number)?.toInt() ?: 1,
                        bitsPerSample = (args["bitsPerSample"] as? Number)?.toInt() ?: 16,
                    ),
                    isFinal = (args["final"] as? Boolean) == true,
                )
                mapOf("ok" to ok)
            }

            "jieli.translation.feedTranslationResult" -> {
                server.translationFeature.feedTranslationResult(
                    srcLang = args["srcLang"] as? String,
                    srcText = args["srcText"] as? String,
                    destLang = args["destLang"] as? String,
                    destText = args["destText"] as? String,
                    requestId = args["requestId"] as? String,
                )
                mapOf("ok" to true)
            }

            "jieli.cmd.send" -> {
                val opCode = (args["opCode"] as? Number)?.toInt()
                    ?: throw DeviceException(
                        DeviceErrorCode.INVALID_ARGUMENT,
                        "opCode required",
                    )
                @Suppress("UNCHECKED_CAST")
                val payload = (args["payload"] as? List<Number>)
                    ?.map { it.toByte() }?.toByteArray()
                    ?: byteArrayOf()
                // 同步等待（5s 超时）—— RCSP 自定义命令通常 < 500ms 返回。
                val deferred = java.util.concurrent.CompletableFuture<ByteArray?>()
                server.customCmdFeature.send(
                    address = deviceId,
                    opCode = opCode,
                    payload = payload,
                    onSuccess = { data -> deferred.complete(data) },
                    onError = { code, msg ->
                        deferred.completeExceptionally(
                            DeviceException("device.feature_failed",
                                "cmd $opCode failed: code=$code msg=${msg ?: ""}")
                        )
                    },
                )
                val resp = try {
                    deferred.get(5, java.util.concurrent.TimeUnit.SECONDS)
                } catch (e: java.util.concurrent.TimeoutException) {
                    throw DeviceException(
                        "device.feature_failed",
                        "cmd $opCode timeout",
                    )
                } catch (e: java.util.concurrent.ExecutionException) {
                    throw e.cause ?: e
                }
                mapOf("response" to resp)
            }

            else -> throw DeviceException(
                DeviceErrorCode.NOT_SUPPORTED,
                "unknown feature \"$featureKey\"",
            )
        }
    }

    override fun callTranslationPort(): DeviceCallTranslationPort = server.callTranslationPort

    override fun otaPort(): DeviceOtaPort? {
        if (DeviceCapability.OTA !in capabilities) return null
        // 懒创建：未 ready 时也允许构造（订阅事件流），但 start() 内部会再校验。
        var port = _otaPort
        if (port == null) {
            synchronized(this) {
                port = _otaPort
                if (port == null && !_disposed) {
                    port = JieliOtaPort(
                        server = server,
                        deviceId = deviceId,
                        cacheDir = File(otaCacheDir, "ota"),
                    )
                    _otaPort = port
                }
            }
        }
        return port
    }

    override fun disconnect() {
        if (_disposed) return
        setState(DeviceConnectionState.DISCONNECTING)
        runCatching { server.connectFeature.disconnect(deviceId) }
        // 真正的 disconnected 状态由 ConnectionStateEvent 推过来
    }

    private fun requireReady() {
        if (_disposed || _state != DeviceConnectionState.READY) {
            throw DeviceException(DeviceErrorCode.NO_ACTIVE_SESSION)
        }
    }
}
