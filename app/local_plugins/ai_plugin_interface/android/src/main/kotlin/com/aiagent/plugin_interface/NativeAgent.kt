package com.aiagent.plugin_interface

import android.content.Context

/**
 * NativeAgent — Agent 类型插件原生接口
 *
 * 每种 Agent 类型（chat, sts, translate, ast）实现此接口。
 * 由 agents_server 通过 NativeAgentRegistry 创建和管理。
 *
 * 生命周期：create → initialize → [connectService → sendText / startListening / ... → disconnectService] → release
 */
interface NativeAgent {

    /** Agent 类型标识（如 "chat", "sts", "translate", "ast"） */
    val agentType: String

    /**
     * 初始化 Agent
     *
     * @param config  Agent 配置（包含服务商 vendor + 各服务 configJson）
     * @param eventSink  事件回调（推送 STT/LLM/TTS/状态事件给 agents_server → Flutter）
     * @param context  Android Context（用于音频、DB 等）
     */
    fun initialize(config: NativeAgentConfig, eventSink: AgentEventSink, context: Context)

    /** 连接服务（E2E Agent：建立 WebSocket；三段式：默认空实现） */
    fun connectService() {}

    /** 断开服务（E2E Agent：关闭 WebSocket；三段式：默认空实现） */
    fun disconnectService() {}

    /** 文本输入 */
    fun sendText(requestId: String, text: String)

    /** 开始语音监听（短语音模式：用户按住按钮） */
    fun startListening()

    /** 停止语音监听（用户松手） */
    fun stopListening()

    /**
     * 切换输入模式
     * @param mode "text" | "short_voice" | "call"
     */
    fun setInputMode(mode: String)

    /**
     * 通用 KV 配置入口（agent 可自由约定 key 语义；不识别的 key 应忽略）。
     *
     * 当前用法：
     * - "bidirectional" = "true" / "false"   — 翻译 agent 互译开关
     * - "direction"     = "src_to_dst" / "dst_to_src" — 翻译 agent 文本输入方向
     */
    fun setOption(key: String, value: String) {}

    /** 打断当前处理（停止 LLM/TTS，恢复 IDLE） */
    fun interrupt()

    /** 释放所有资源 */
    fun release()

    // ── 外部音频源（通话翻译等场景） ────────────────────────────────────────
    //
    // 默认实现 = 不支持。翻译型 agent（ast-translate / translate）按需 override，
    // 把帧透传给底层 NativeAstService.pushExternalAudioFrame。
    //
    // 协议：调用方先 externalAudioCapability() 协商格式，再 startExternalAudio(format)，
    // 之后高频 pushExternalAudioFrame(bytes)，结束 stopExternalAudio()。
    // 与既有 startListening()/stopListening()（自家 mic 模式）互斥，agent 内部按
    // 当前活跃模式拒绝跨模式调用。

    /** 描述本 agent 对外部音频源的接受能力。默认 = 不支持。 */
    fun externalAudioCapability(): ExternalAudioCapability =
        ExternalAudioCapability.UNSUPPORTED

    /**
     * 启动外部音频源模式。
     *
     * @param format 协商好的输入格式（必须落在 [externalAudioCapability] 内）
     * @param sink   下行 TTS 字节回写通道（agent / service 把翻译结果的 TTS 帧发给调用方）
     * @throws UnsupportedOperationException 默认不支持。
     */
    fun startExternalAudio(format: ExternalAudioFormat, sink: ExternalAudioSink) {
        throw UnsupportedOperationException(
            "agent ${this::class.simpleName} does not support external audio source"
        )
    }

    /** 推送一帧外部音频。格式必须与 [startExternalAudio] 协商一致。 */
    fun pushExternalAudioFrame(frame: ByteArray) {}

    /** 停止外部音频源模式。 */
    fun stopExternalAudio() {}
}
