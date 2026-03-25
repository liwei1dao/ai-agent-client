package com.aiagent.plugin_interface

import android.content.Context

/**
 * NativeAgent — Agent 类型插件原生接口
 *
 * 每种 Agent 类型（chat, sts, translate, ast）实现此接口。
 * 由 agents_server 通过 NativeAgentRegistry 创建和管理。
 *
 * 生命周期：create → initialize → [sendText / startListening / ...] → release
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

    /** 打断当前处理（停止 LLM/TTS，恢复 IDLE） */
    fun interrupt()

    /** 释放所有资源 */
    fun release()
}
