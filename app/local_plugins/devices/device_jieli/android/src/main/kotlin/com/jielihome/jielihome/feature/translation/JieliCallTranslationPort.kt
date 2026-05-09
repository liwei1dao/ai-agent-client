package com.jielihome.jielihome.feature.translation

import android.util.Log
import com.aiagent.device_plugin_interface.CallAudioCodec
import com.aiagent.device_plugin_interface.CallAudioFormat
import com.aiagent.device_plugin_interface.CallAudioFrame
import com.aiagent.device_plugin_interface.CallTranslationError
import com.aiagent.device_plugin_interface.CallTranslationLeg
import com.aiagent.device_plugin_interface.DeviceCallTranslationPort
import com.aiagent.device_plugin_interface.TranslatedAudioFrame
import com.jielihome.jielihome.core.JieliHomeServer
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow

/**
 * `DeviceCallTranslationPort` 的杰理实现。
 *
 * 当前阶段策略：**只支持 PCM_S16LE / 16kHz / mono / 20ms**。
 * 新版 SDK 已经在 native 内部把耳机端 OPUS 解码成 PCM 上推（见 [TranslationFeature]
 * 的 `mode` handlers），上层零编解码即可贯通。OPUS 直通模式后续按需补。
 *
 * # enter / exit 与 SDK bridge 的关系
 * - [enter] 时把 [JieliHomeServer.defaultBridge]（EventChannel → Dart 的桥）替换为
 *   本实现内的 capture bridge：拦截 `IN_UPLINK` / `IN_DOWNLINK` 上推的 PCM 帧，
 *   翻译成 [CallAudioFrame] 写入 [audioFrames] 流；同时把 `emitError` 接到
 *   [errors] 流。
 * - 期间 Dart 的 `device_jieli/event` 不会再收到翻译音频事件——这正是"完全 native
 *   直连翻译服务"的预期路径，与 `translate_server` native 编排器配套。
 * - [exit] 时还原默认桥，Dart 端的 EventChannel 恢复正常使用。
 *
 * # TTS 回灌
 * 编排器把翻译完成的 PCM 通过 [reportTranslated] 回写：
 * - `CallTranslationLeg.UPLINK`   → SDK 的 `OUT_UPLINK`（对方耳机听）
 * - `CallTranslationLeg.DOWNLINK` → SDK 的 `OUT_DOWNLINK`（本机用户耳机听）
 *
 * # 线程安全
 * `enter`/`exit`/`reportTranslated` 通过 `synchronized(this)` 互斥；
 * SharedFlow `tryEmit` 自身线程安全，capture bridge 可被任意线程回调。
 */
class JieliCallTranslationPort(
    private val server: JieliHomeServer,
) : DeviceCallTranslationPort {

    companion object {
        private const val TAG = "JieliCallTransPort"
        private val PCM_16K_MONO_20MS = CallAudioFormat.PCM_S16LE_16K_MONO_20MS
    }

    private val _audioFrames = MutableSharedFlow<CallAudioFrame>(
        replay = 0,
        extraBufferCapacity = 128,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )
    private val _errors = MutableSharedFlow<CallTranslationError>(
        replay = 0,
        extraBufferCapacity = 16,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )

    @Volatile private var entered = false
    @Volatile private var savedBridge: TranslationAudioBridge? = null

    override fun supportedSourceFormats(): Set<CallAudioFormat> = setOf(PCM_16K_MONO_20MS)
    override fun supportedSinkFormats(): Set<CallAudioFormat> = setOf(PCM_16K_MONO_20MS)

    override val audioFrames: Flow<CallAudioFrame> = _audioFrames.asSharedFlow()
    override val errors: Flow<CallTranslationError> = _errors.asSharedFlow()

    @Synchronized
    override fun enter(sourceFormat: CallAudioFormat) {
        require(sourceFormat == PCM_16K_MONO_20MS) {
            "JieliCallTranslationPort only supports PCM_S16LE/16k/mono/20ms (got $sourceFormat)"
        }
        check(!entered) { "device.call_translation.busy" }

        val translationFeature = server.translationFeature

        // 调试：统计 SDK 给我们推了多少帧、按 leg 分桶；每秒打一次。
        val countByStream = java.util.concurrent.ConcurrentHashMap<String, Long>()
        var lastReportMs = System.currentTimeMillis()

        val captureBridge = object : TranslationAudioBridge {
            override fun emitAudioFrame(
                modeId: Int,
                streamId: String,
                pcm: ByteArray,
                format: AudioFormat,
                seq: Long,
                tsMs: Long,
                isFinal: Boolean,
            ) {
                // 调试用：周期性打印 SDK 上推帧统计，确认设备端有没有真出 PCM。
                countByStream.merge(streamId, 1L) { old, _ -> old + 1L }
                val now = System.currentTimeMillis()
                if (now - lastReportMs >= 1000L) {
                    Log.d(TAG, "SDK frame stats (last 1s): $countByStream  fmt=${format.sampleRate}Hz/${format.channels}ch")
                    countByStream.clear()
                    lastReportMs = now
                }
                val leg = when (streamId) {
                    TranslationStreams.IN_UPLINK -> CallTranslationLeg.UPLINK
                    TranslationStreams.IN_DOWNLINK -> CallTranslationLeg.DOWNLINK
                    else -> return // ignore non-call streams in this mode
                }
                val frame = CallAudioFrame(
                    leg = leg,
                    codec = CallAudioCodec.PCM_S16LE,
                    sampleRate = format.sampleRate,
                    channels = format.channels,
                    bytes = pcm,
                    sequence = seq,
                    timestampUs = tsMs * 1000L,
                )
                if (!_audioFrames.tryEmit(frame)) {
                    Log.w(TAG, "audioFrames buffer overflow; dropped seq=$seq leg=$leg")
                }
            }

            override fun emitTranslationResult(
                modeId: Int,
                srcLang: String?, srcText: String?,
                destLang: String?, destText: String?,
                requestId: String?,
            ) {
                // 字幕在 native 编排器里由 agent 直接出，不依赖这个回调；忽略。
            }

            override fun emitLog(modeId: Int, content: String) {
                Log.d(TAG, "translation log: modeId=$modeId $content")
            }

            override fun emitError(modeId: Int, code: Int, message: String?) {
                _errors.tryEmit(
                    CallTranslationError(
                        code = "device.feature_failed",
                        message = "code=$code msg=${message ?: ""}",
                    )
                )
            }

            override fun feedTranslatedAudio(
                modeId: Int,
                outputStreamId: String,
                pcm: ByteArray,
                format: AudioFormat,
                isFinal: Boolean,
            ): Boolean {
                // capture bridge 不负责回灌——编排器走 [reportTranslated] 直接调
                // server.translationFeature.feedTranslatedAudio。
                return false
            }
        }

        savedBridge = server.defaultBridge
        server.setTranslationBridge(captureBridge)

        val result = translationFeature.start(
            TranslationModeIds.MODE_CALL_TRANSLATION,
            emptyMap(),
        )
        if (result.isFailure) {
            // 启动失败：还原桥并抛出
            savedBridge?.let { runCatching { server.setTranslationBridge(it) } }
            savedBridge = null
            throw IllegalStateException(
                "failed to enter MODE_CALL_TRANSLATION: ${result.exceptionOrNull()?.message}",
                result.exceptionOrNull(),
            )
        }
        entered = true
        Log.d(TAG, "entered MODE_CALL_TRANSLATION")
    }

    @Synchronized
    override fun reportTranslated(frame: TranslatedAudioFrame) {
        check(entered) { "device.call_translation.not_active" }
        require(frame.codec == CallAudioCodec.PCM_S16LE) {
            "JieliCallTranslationPort only accepts PCM_S16LE for sink (got ${frame.codec})"
        }
        val streamId = when (frame.leg) {
            CallTranslationLeg.UPLINK -> TranslationStreams.OUT_UPLINK
            CallTranslationLeg.DOWNLINK -> TranslationStreams.OUT_DOWNLINK
        }
        val ok = server.translationFeature.feedTranslatedAudio(
            outputStreamId = streamId,
            pcm = frame.bytes,
            format = AudioFormat(
                sampleRate = frame.sampleRate,
                channels = frame.channels,
                bitsPerSample = 16,
            ),
            isFinal = frame.isFinal,
        )
        if (!ok) {
            Log.w(TAG, "feedTranslatedAudio rejected: streamId=$streamId leg=${frame.leg}")
        }
    }

    @Synchronized
    override fun exit() {
        if (!entered) return
        entered = false
        runCatching { server.translationFeature.stop() }
        savedBridge?.let { runCatching { server.setTranslationBridge(it) } }
        savedBridge = null
        Log.d(TAG, "exited call translation")
    }
}
