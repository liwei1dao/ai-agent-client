package com.aiagent.plugin_interface

/**
 * LLM（大语言模型）服务原生接口
 *
 * 实现方：llm_openai 等服务插件
 * 使用方：agent_chat 等 Agent 类型插件
 *
 * 职责：HTTP SSE 流式推理 + 工具调用 + 取消
 */
interface NativeLlmService {

    /**
     * 初始化 LLM 服务
     * @param configJson  服务配置 JSON（apiKey, baseUrl, model, temperature 等）
     */
    fun initialize(configJson: String)

    /**
     * 流式对话
     *
     * 挂起函数：直到推理完成才返回完整文本。
     * 通过 callback 推送流式增量。
     *
     * @param requestId  请求 ID
     * @param messages   消息历史 [{"role":"user","content":"..."},...]
     * @param tools      工具定义（MCP / Function Calling）
     * @param callback   流式回调
     * @return 完整的 assistant 回复文本
     */
    suspend fun chat(
        requestId: String,
        messages: List<Map<String, Any>>,
        tools: List<Map<String, Any>> = emptyList(),
        callback: LlmCallback,
    ): String

    /** 取消当前请求 */
    fun cancel()
}

/**
 * LLM 流式回调
 */
interface LlmCallback {
    /** 第一个 token 到达 */
    fun onFirstToken(textDelta: String)

    /** 后续 token 增量 */
    fun onTextDelta(textDelta: String)

    /** 思考增量（部分模型支持） */
    fun onThinkingDelta(delta: String)

    /** 工具调用开始 */
    fun onToolCallStart(id: String, name: String)

    /** 工具调用参数增量 */
    fun onToolCallArguments(delta: String)

    /** 工具调用结果 */
    fun onToolCallResult(result: String)

    /** 推理完成 */
    fun onDone(fullText: String)

    /** 错误 */
    fun onError(code: String, message: String)
}
