package com.aiagent.plugin_interface

import android.content.Context

/**
 * STS（端到端语音对话）服务原生接口
 *
 * 实现方：sts_volcengine 等服务插件
 * 使用方：agent_sts_chat
 *
 * 职责：WebSocket 连接 + 双向音频流（麦克风 → 服务端 → AudioTrack 播放）
 * 服务端完成 ASR → LLM → TTS 全流程。
 */
interface NativeStsService {

    /**
     * 初始化 STS 服务
     * @param configJson  服务配置 JSON（apiKey, appId, voiceName 等）
     * @param context     Android Context
     */
    fun initialize(configJson: String, context: Context)

    /**
     * 建立 WebSocket 连接
     * 连接建立后通过 callback 推送事件
     */
    fun connect(callback: StsCallback)

    /** 开始发送麦克风音频（WebSocket 已连接） */
    fun startAudio()

    /** 停止发送麦克风音频（WebSocket 保持连接） */
    fun stopAudio()

    /** 打断：清空 TTS 播放缓冲，停止当前回复 */
    fun interrupt()

    /** 释放所有资源（断开 WebSocket + 关闭音频） */
    fun release()

    // ── 外部音频源 ──────────────────────────────────────────────────
    //
    // 与 [startAudio] / [stopAudio]（自家 mic 模式）互斥。

    fun externalAudioCapability(): ExternalAudioCapability =
        ExternalAudioCapability.UNSUPPORTED

    /**
     * @param sink TTS 下行字节回写通道（service 把服务端返回的 PCM/OPUS 帧通过 sink 给调用方）
     */
    fun startExternalAudio(format: ExternalAudioFormat, sink: ExternalAudioSink) {
        throw UnsupportedOperationException(
            "service ${this::class.simpleName} does not support external audio source"
        )
    }

    fun pushExternalAudioFrame(frame: ByteArray) {}

    fun stopExternalAudio() {}
}

/**
 * STS 事件回调
 */
interface StsCallback {
    /** WebSocket 连接建立 */
    fun onConnected()

    /** 用户语音识别中间结果 */
    fun onSttPartialResult(text: String)

    /** 用户语音识别最终结果 */
    fun onSttFinalResult(text: String)

    /** 收到 TTS 音频数据（PCM） */
    fun onTtsAudioChunk(pcmData: ByteArray)

    /** 一句话回复结束 */
    fun onSentenceDone(text: String)

    /** WebSocket 断开连接 */
    fun onDisconnected()

    /** 错误 */
    fun onError(code: String, message: String)

    /** 检测到用户开口说话（用于打断） */
    fun onSpeechStart()

    /** 状态变更 */
    fun onStateChanged(state: String)
}
