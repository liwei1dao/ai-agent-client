package com.aiagent.plugin_interface

import android.content.Context

/**
 * STT（语音识别）服务原生接口
 *
 * 实现方：stt_azure 等服务插件
 * 使用方：agent_chat, agent_translate 等 Agent 类型插件
 *
 * 职责：麦克风采集 + 语音识别 + VAD 检测
 */
interface NativeSttService {

    /**
     * 初始化 STT 服务
     * @param configJson  服务配置 JSON（apiKey, region, language 等）
     * @param context     Android Context
     */
    fun initialize(configJson: String, context: Context)

    /**
     * 开始监听（打开麦克风，启动识别）
     * 通过 callback 持续推送事件
     */
    fun startListening(callback: SttCallback)

    /** 停止监听（关闭麦克风） */
    fun stopListening()

    /** 释放资源 */
    fun release()
}

/**
 * STT 事件回调
 */
interface SttCallback {
    /** 麦克风已打开，开始监听 */
    fun onListeningStarted()

    /** 识别中间结果（流式） */
    fun onPartialResult(text: String)

    /** 识别最终结果 */
    fun onFinalResult(text: String)

    /** VAD 检测到语音开始 */
    fun onVadSpeechStart()

    /** VAD 检测到语音结束 */
    fun onVadSpeechEnd()

    /** 监听已停止（麦克风关闭） */
    fun onListeningStopped()

    /** 错误 */
    fun onError(code: String, message: String)
}
