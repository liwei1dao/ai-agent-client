package com.aiagent.plugin_interface

/**
 * MCP（Model Context Protocol）服务原生接口
 *
 * 实现方：mcp_streamable_http 等传输厂商插件
 * 使用方：agent_chat 等 Agent 类型插件
 *
 * 单实例对应单 server。多 server 聚合由 agent 容器内的 McpRouter 负责。
 *
 * 生命周期：`uninitialized → initialize(...) → ready → callTool/listTools → dispose → disposed`
 */
interface NativeMcpService {

    /**
     * 握手并就绪
     *
     * @param configJson  序列化后的 McpServerConfig（id/name/url/authHeader/enabledTools/timeoutSeconds/extraHeaders）
     * @throws Exception  握手失败时抛出，调用方据此把该 server 标记为不可用
     */
    suspend fun initialize(configJson: String)

    /**
     * 拉取该 server 的工具列表（按 enabledTools 白名单过滤）
     *
     * @return List<Map> 每条 = {"name", "description", "inputSchema":Map, "serverId"}
     */
    suspend fun listTools(): List<Map<String, Any?>>

    /**
     * 调用工具
     *
     * @param toolName  工具名
     * @param argsJson  JSON 字符串形式的参数对象
     * @return Map  {"content": String, "isError": Boolean}
     */
    suspend fun callTool(toolName: String, argsJson: String): Map<String, Any?>

    /** 释放资源（关闭 OkHttp client、清理 sessionId 等） */
    fun dispose()
}
