package com.aiagent.plugin_interface

import android.content.Context

/**
 * STT（语音识别）服务原生接口
 *
 * 实现方：stt_azure 等服务插件
 * 使用方：agent_chat, agent_translate 等 Agent 类型插件
 *
 * 职责：麦克风采集 + 语音识别 + VAD 检测
 *
 * **强约束**：新增 STT 厂商实现**必须**支持外部音频源（参见下方"外部音频源"小节），
 * 否则将无法用于通话翻译 / 面对面翻译等需要由调用方推送 PCM 的复合场景。默认实现
 * 抛 UnsupportedOperationException 仅作为编译兜底，运行期触达即视为接口未实现完整。
 */
interface NativeSttService {

    /**
     * 初始化 STT 服务
     * @param configJson  服务配置 JSON（apiKey, region, language 等）
     * @param context     Android Context
     */
    fun initialize(configJson: String, context: Context)

    /**
     * 是否支持语言识别（自动检测说话者语言）。
     *
     * 上层（如 TranslateAgentSession 的"互译"开关）据此决定是否暴露互译 UI。
     * 厂商若声明 true，必须在 [SttCallback.onFinalResult] / [SttCallback.onPartialResult]
     * 的 detectedLang 参数里给出识别到的 BCP-47 语言码（如 "en-US"）。
     */
    fun supportsLanguageDetection(): Boolean = false

    /**
     * 开始监听（打开麦克风，启动识别）
     * 通过 callback 持续推送事件
     */
    fun startListening(callback: SttCallback)

    /** 停止监听（关闭麦克风） */
    fun stopListening()

    /** 释放资源 */
    fun release()

    // ── 外部音频源 ──────────────────────────────────────────────────
    //
    // 与 [startListening] / [stopListening]（自家 mic 模式）互斥。
    // 通话翻译场景：调用方先协商格式，再启动外部模式（绑定 callback），
    // 之后高频 [pushExternalAudioFrame] 把耳机解码后的 PCM 喂进识别引擎；
    // 文本事件仍通过 [SttCallback] 回吐。

    fun externalAudioCapability(): ExternalAudioCapability =
        ExternalAudioCapability.UNSUPPORTED

    /**
     * 启动外部音频源识别。
     *
     * @param format    协商好的输入格式（必须落在 [externalAudioCapability] 内）
     * @param callback  识别事件回调（与 [startListening] 用同一组事件）
     * @throws UnsupportedOperationException 默认不支持。
     */
    fun startExternalAudio(format: ExternalAudioFormat, callback: SttCallback) {
        throw UnsupportedOperationException(
            "stt service ${this::class.simpleName} does not support external audio source"
        )
    }

    /** 推送一帧外部音频（格式必须与 [startExternalAudio] 协商一致）。 */
    fun pushExternalAudioFrame(frame: ByteArray) {}

    /** 停止外部音频源识别。 */
    fun stopExternalAudio() {}
}

/**
 * STT 事件回调
 */
interface SttCallback {
    /** 麦克风已打开，开始监听 */
    fun onListeningStarted()

    /** 识别中间结果（流式） */
    fun onPartialResult(text: String)

    /** 识别中间结果（流式）+ 检测到的语言。
     *  默认转发到 [onPartialResult]。支持语言识别的厂商应调用此重载。 */
    fun onPartialResult(text: String, detectedLang: String?) {
        onPartialResult(text)
    }

    /** 识别最终结果 */
    fun onFinalResult(text: String)

    /** 识别最终结果 + 检测到的语言。
     *  默认转发到 [onFinalResult]。支持语言识别的厂商应调用此重载。 */
    fun onFinalResult(text: String, detectedLang: String?) {
        onFinalResult(text)
    }

    /** VAD 检测到语音开始 */
    fun onVadSpeechStart()

    /** VAD 检测到语音结束 */
    fun onVadSpeechEnd()

    /** 监听已停止（麦克风关闭） */
    fun onListeningStopped()

    /** 错误 */
    fun onError(code: String, message: String)
}
