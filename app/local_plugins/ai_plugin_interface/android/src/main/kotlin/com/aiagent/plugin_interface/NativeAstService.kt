package com.aiagent.plugin_interface

import android.content.Context

/**
 * AST（端到端语音翻译）服务原生接口
 *
 * 实现方：ast_polychat / ast_volcengine 等服务插件
 * 使用方：agent_ast_translate
 *
 * 职责：建立长连接 + 双向音频流（麦克风 → 服务端 ASR → 翻译 → TTS 播放）
 * 服务端完成全流程，客户端按 STS 五件套生命周期向上派发识别事件。
 */
interface NativeAstService {

    /**
     * 初始化 AST 服务
     * @param configJson  服务配置 JSON（apiKey, appId, srcLang, dstLang 等）
     * @param context     Android Context
     */
    fun initialize(configJson: String, context: Context)

    /**
     * 建立连接
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
 * AST 识别事件归属的角色
 */
enum class AstRole {
    SOURCE,      // 原文（用户语音识别结果）
    TRANSLATED,  // 译文（服务端翻译结果）
}

/**
 * AST 事件回调。
 *
 * 与 STS 协议对齐的识别五件套（每事件携带 requestId + role，
 * recognitionEnd 的 role 为 null）：
 *
 *   recognitionStart → recognizing* → recognized* → recognitionDone → recognitionEnd
 *
 * 文本语义：
 *   - recognizing.text = 累计快照（覆盖语义）
 *   - recognized.text  = 本段定稿（累加语义）
 *
 * 闭合铁律：每个 recognitionStart(role) 必有 recognitionDone(role)；
 *          每个 requestId 必有一次 recognitionEnd。
 */
interface AstCallback {
    /** 连接建立 */
    fun onConnected()

    /** 连接断开 */
    fun onDisconnected()

    /** 一个 (role, requestId) 的识别链路开始 */
    fun onRecognitionStart(role: AstRole, requestId: String)

    /** 中间态：text 必须是从本段起点的累计快照 */
    fun onRecognizing(role: AstRole, requestId: String, text: String)

    /** 定稿态：text 是本段最终文本 */
    fun onRecognized(role: AstRole, requestId: String, text: String)

    /** 单 role 识别链路闭合 */
    fun onRecognitionDone(role: AstRole, requestId: String)

    /** 整个 requestId 回合关闭（所有 role 都 done 之后） */
    fun onRecognitionEnd(requestId: String)

    /** 识别阶段错误（不关闭流） */
    fun onRecognitionError(requestId: String?, role: AstRole?, code: String, message: String)

    /** 非归属错误（连接层 / 未知异常） */
    fun onError(code: String, message: String)
}
