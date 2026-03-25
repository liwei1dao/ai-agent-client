package com.aiagent.plugin_interface

import android.content.Context

/**
 * TTS（语音合成）服务原生接口
 *
 * 实现方：tts_azure 等服务插件
 * 使用方：agent_chat, agent_translate 等 Agent 类型插件
 *
 * 职责：文本合成 + 音频播放 + 打断控制
 */
interface NativeTtsService {

    /**
     * 初始化 TTS 服务
     * @param configJson  服务配置 JSON（apiKey, region, voiceName 等）
     * @param context     Android Context
     */
    fun initialize(configJson: String, context: Context)

    /**
     * 合成并播放文本
     *
     * 挂起函数：直到播放完成或被打断才返回。
     * 通过 callback 推送进度事件。
     *
     * @param requestId  请求 ID（用于匹配事件）
     * @param text       要合成的文本
     * @param callback   播放进度回调
     */
    suspend fun speak(requestId: String, text: String, callback: TtsCallback)

    /** 停止当前播放（触发 playbackInterrupted） */
    fun stop()

    /** 释放资源 */
    fun release()
}

/**
 * TTS 事件回调
 */
interface TtsCallback {
    /** 合成请求已发出 */
    fun onSynthesisStart()

    /** 合成完成，音频数据就绪 */
    fun onSynthesisReady(durationMs: Int)

    /** 开始播放 */
    fun onPlaybackStart()

    /** 播放进度 */
    fun onPlaybackProgress(progressMs: Int)

    /** 播放完成 */
    fun onPlaybackDone()

    /** 播放被打断 */
    fun onPlaybackInterrupted()

    /** 错误 */
    fun onError(code: String, message: String)
}
