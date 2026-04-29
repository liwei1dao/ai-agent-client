package com.jielihome.jielihome.bridge

import android.content.Context
import com.jielihome.jielihome.core.JieliHomeServer
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * MethodChannel 路由层：把 Dart 调用映射到 server 内的 feature 模块。
 * Plugin 类不直接处理任何业务逻辑，只装配 router。
 */
class MethodRouter(
    private val context: Context,
    private val server: JieliHomeServer,
) : MethodChannel.MethodCallHandler {

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "getPlatformVersion" ->
                    result.success("Android ${android.os.Build.VERSION.RELEASE}")

                "initialize" -> {
                    server.initialize(
                        context = context,
                        multiDevice = call.argument<Boolean>("multiDevice") ?: true,
                        skipNoNameDev = call.argument<Boolean>("skipNoNameDev") ?: false,
                        enableLog = call.argument<Boolean>("enableLog") ?: false,
                    )
                    result.success(true)
                }

                "startScan" -> {
                    val timeout = call.argument<Int>("timeoutMs") ?: 30000
                    server.scanFeature.startScan(timeout)
                        .fold({ result.success(true) },
                              { result.error("SCAN_FAILED", it.message, null) })
                }

                "stopScan" -> { server.scanFeature.stopScan(); result.success(true) }

                "isScanning" -> result.success(server.scanFeature.isScanning())

                "connect" -> {
                    val mac = call.argument<String>("address")
                        ?: return result.error("BAD_ARG", "address required", null)
                    server.connectFeature.connect(
                        bleAddress = mac,
                        edrAddress = call.argument<String>("edrAddr"),
                        deviceType = call.argument<Int>("deviceType") ?: -1,
                        connectWay = call.argument<Int>("connectWay") ?: 0,
                    ).fold({ result.success(true) },
                           { result.error("CONNECT_FAILED", it.message, null) })
                }

                "disconnect" -> {
                    val mac = call.argument<String>("address")
                        ?: return result.error("BAD_ARG", "address required", null)
                    server.connectFeature.disconnect(mac)
                        .fold({ result.success(true) },
                              { result.error("DISCONNECT_FAILED", it.message, null) })
                }

                "isConnected" -> {
                    val mac = call.argument<String>("address")
                        ?: return result.error("BAD_ARG", "address required", null)
                    result.success(server.connectFeature.isConnected(mac))
                }

                "connectedDevice" -> {
                    val d = server.connectFeature.connectedDevice()
                    if (d == null) result.success(null)
                    else result.success(
                        mapOf(
                            "address" to d.address,
                            "name" to runCatching { d.name }.getOrNull()
                        )
                    )
                }

                "deviceSnapshot" -> {
                    val mac = call.argument<String>("address")
                        ?: return result.error("BAD_ARG", "address required", null)
                    result.success(server.deviceInfoFeature.snapshot(mac))
                }

                "queryTargetInfo" -> {
                    val mac = call.argument<String>("address")
                        ?: return result.error("BAD_ARG", "address required", null)
                    val mask = call.argument<Int>("mask") ?: 0x0F
                    server.deviceInfoFeature.queryTargetInfo(
                        mac, mask,
                        onSuccess = { result.success(it) },
                        onError = { c, m -> result.error("TARGET_INFO_ERR", m, c) }
                    )
                }

                "sendCustomCmd" -> {
                    val mac = call.argument<String>("address")
                        ?: return result.error("BAD_ARG", "address required", null)
                    val opCode = call.argument<Int>("opCode")
                        ?: return result.error("BAD_ARG", "opCode required", null)
                    val payload = call.argument<ByteArray>("payload") ?: ByteArray(0)
                    server.customCmdFeature.send(
                        mac, opCode, payload,
                        onSuccess = { result.success(it) },
                        onError = { c, m -> result.error("CUSTOM_CMD_ERR", m, c) }
                    )
                }

                "startTranslation" -> {
                    val modeId = call.argument<Int>("modeId")
                        ?: return result.error("BAD_ARG", "modeId required", null)
                    @Suppress("UNCHECKED_CAST")
                    val args = (call.argument<Map<String, Any?>>("args") ?: emptyMap())
                    server.translationFeature.start(modeId, args)
                        .fold({ result.success(true) },
                              { result.error("TRANSLATION_ERR", it.message, null) })
                }

                "stopTranslation" -> {
                    server.translationFeature.stop(); result.success(true)
                }

                "translationStatus" -> result.success(
                    mapOf(
                        "working" to server.translationFeature.isWorking(),
                        "modeId" to server.translationFeature.currentModeId(),
                        "inputStreams" to server.translationFeature.currentInputStreams(),
                        "outputStreams" to server.translationFeature.currentOutputStreams()
                    )
                )

                "feedTranslatedAudio" -> {
                    val streamId = call.argument<String>("streamId")
                        ?: return result.error("BAD_ARG", "streamId required", null)
                    val pcm = call.argument<ByteArray>("pcm")
                        ?: return result.error("BAD_ARG", "pcm required", null)
                    val sampleRate = call.argument<Int>("sampleRate") ?: 16000
                    val channels = call.argument<Int>("channels") ?: 1
                    val bits = call.argument<Int>("bitsPerSample") ?: 16
                    val isFinal = call.argument<Boolean>("final") ?: false
                    val ok = server.translationFeature.feedTranslatedAudio(
                        streamId, pcm,
                        com.jielihome.jielihome.feature.translation.AudioFormat(sampleRate, channels, bits),
                        isFinal
                    )
                    result.success(ok)
                }

                "feedTranslationResult" -> {
                    server.translationFeature.feedTranslationResult(
                        srcLang = call.argument<String>("srcLang"),
                        srcText = call.argument<String>("srcText"),
                        destLang = call.argument<String>("destLang"),
                        destText = call.argument<String>("destText"),
                        requestId = call.argument<String>("requestId"),
                    )
                    result.success(true)
                }

                "isSupportCallTranslationWithStereo" -> {
                    val mac = call.argument<String>("address")
                    result.success(server.translationFeature.isSupportCallTranslationWithStereo(mac))
                }

                "feedAudioFilePcm" -> {
                    val pcm = call.argument<ByteArray>("pcm")
                        ?: return result.error("BAD_ARG", "pcm required", null)
                    val sampleRate = call.argument<Int>("sampleRate") ?: 16000
                    result.success(server.translationFeature.feedAudioFilePcm(pcm, sampleRate))
                }

                "speechIsRecording" ->
                    result.success(server.speechFeature.isRecording(call.argument<String>("address")))

                "speechStart" -> {
                    server.speechFeature.start(
                        address = call.argument<String>("address"),
                        voiceType = call.argument<Int>("voiceType")
                            ?: com.jieli.bluetooth.bean.record.RecordParam.VOICE_TYPE_OPUS,
                        sampleRate = call.argument<Int>("sampleRate")
                            ?: com.jieli.bluetooth.bean.record.RecordParam.SAMPLE_RATE_16K,
                        vadWay = call.argument<Int>("vadWay")
                            ?: com.jieli.bluetooth.bean.record.RecordParam.VAD_WAY_DEVICE,
                        onResult = { ok, msg ->
                            if (ok) result.success(true)
                            else result.error("SPEECH_START_ERR", msg, null)
                        }
                    )
                }

                "speechStop" -> {
                    server.speechFeature.stop(
                        address = call.argument<String>("address"),
                        reason = call.argument<Int>("reason")
                            ?: com.jieli.bluetooth.bean.record.RecordState.REASON_NORMAL,
                        onResult = { ok, msg ->
                            if (ok) result.success(true)
                            else result.error("SPEECH_STOP_ERR", msg, null)
                        }
                    )
                }

                "otaStart" -> {
                    val path = call.argument<String>("firmwareFilePath")
                        ?: return result.error("BAD_ARG", "firmwareFilePath required", null)
                    server.otaFeature.start(
                        address = call.argument<String>("address"),
                        firmwareFilePath = path,
                        blockSize = call.argument<Int>("blockSize") ?: 512,
                        fileFlagBytes = call.argument<ByteArray>("fileFlag") ?: ByteArray(0),
                    )
                    result.success(true)
                }

                "otaCancel" -> { server.otaFeature.cancel(); result.success(true) }

                "otaIsRunning" -> result.success(server.otaFeature.isRunning())

                else -> result.notImplemented()
            }
        } catch (t: Throwable) {
            result.error("PLUGIN_ERR", t.message, t.stackTraceToString())
        }
    }
}
