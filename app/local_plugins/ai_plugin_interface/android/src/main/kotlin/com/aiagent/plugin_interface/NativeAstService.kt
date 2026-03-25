package com.aiagent.plugin_interface

import android.content.Context

/**
 * AST（端到端语音翻译）服务原生接口
 *
 * 实现方：ast_volcengine 等服务插件
 * 使用方：ast_agent_translate
 *
 * 职责：WebSocket 连接 + 双向音频流（麦克风 → 服务端翻译 → AudioTrack 播放）
 * 服务端完成 ASR → 翻译 → TTS 全流程。
 */
interface NativeAstService {

    /**
     * 初始化 AST 服务
     * @param configJson  服务配置 JSON（apiKey, appId, srcLang, dstLang 等）
     * @param context     Android Context
     */
    fun initialize(configJson: String, context: Context)

    /**
     * 建立 WebSocket 连接
     * 连接建立后通过 callback 推送事件
     */
    fun connect(callback: AstCallback)

    /** 开始发送麦克风音频 */
    fun startAudio()

    /** 停止发送麦克风音频 */
    fun stopAudio()

    /** 打断：清空 TTS 播放缓冲 */
    fun interrupt()

    /** 释放所有资源 */
    fun release()
}

/**
 * AST 事件回调
 */
interface AstCallback {
    /** WebSocket 连接建立 */
    fun onConnected()

    /** 源语言字幕（用户语音识别文字） */
    fun onSourceSubtitle(text: String)

    /** 翻译后字幕 */
    fun onTranslatedSubtitle(text: String)

    /** 收到 TTS 音频数据（PCM） */
    fun onTtsAudioChunk(pcmData: ByteArray)

    /** WebSocket 断开连接 */
    fun onDisconnected()

    /** 错误 */
    fun onError(code: String, message: String)

    /** 检测到用户开口说话（用于打断） */
    fun onSpeechStart()

    /** 状态变更 */
    fun onStateChanged(state: String)
}
