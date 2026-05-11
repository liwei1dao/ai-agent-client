package com.aiagent.plugin_interface

import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/**
 * 多 MCP server 聚合路由器（Native 端）
 *
 * - 持有多个 NativeMcpService 实例（每个 server 一个）
 * - 聚合所有工具列表（toolName 冲突 = 先到先得）
 * - 按 toolName 路由 callTool
 *
 * 由 agent 容器（如 ChatAgentSession）独占持有，生命周期与 agent 一致。
 */
class NativeMcpRouter {

    companion object {
        private const val TAG = "NativeMcpRouter"
    }

    private data class ToolEntry(
        val name: String,
        val description: String,
        val inputSchema: Map<String, Any?>,
        val serverId: String,
    )

    private val services = mutableMapOf<String, NativeMcpService>() // serverId -> service
    private val toolByName = linkedMapOf<String, ToolEntry>()
    private val warnings = mutableListOf<String>()

    /**
     * 添加并初始化一个 server。失败不抛，转为 warning，使其它 server 可继续工作。
     *
     * @param serverConfig 单 server 的完整配置 JSON（含 id/name/url/authHeader 等）
     * @param transport 传输协议（默认 streamable_http）
     */
    suspend fun addServer(
        serverConfig: JSONObject,
        transport: String = "streamable_http",
    ) {
        val serverId = serverConfig.optString("id", "")
        if (serverId.isBlank()) {
            warnings.add("addServer: missing server id")
            return
        }
        if (services.containsKey(serverId)) return

        val service: NativeMcpService = try {
            NativeServiceRegistry.createMcp(transport)
        } catch (e: Exception) {
            warnings.add("addServer($serverId): no transport \"$transport\": ${e.message}")
            return
        }

        try {
            service.initialize(serverConfig.toString())
            val tools = service.listTools()
            services[serverId] = service
            for (t in tools) {
                val name = t["name"] as? String ?: continue
                if (toolByName.containsKey(name)) {
                    warnings.add("tool \"$name\" from server \"$serverId\" shadowed by earlier server")
                    continue
                }
                @Suppress("UNCHECKED_CAST")
                val schema = (t["inputSchema"] as? Map<String, Any?>) ?: emptyMap()
                toolByName[name] = ToolEntry(
                    name = name,
                    description = (t["description"] as? String) ?: "",
                    inputSchema = schema,
                    serverId = serverId,
                )
            }
            Log.d(TAG, "addServer($serverId): ${tools.size} tools")
        } catch (e: Exception) {
            warnings.add("connect server \"$serverId\" failed: ${e.message}")
            try {
                service.dispose()
            } catch (_: Exception) {}
        }
    }

    /** OpenAI tools 数组（每条 = {"type":"function","function":{"name","description","parameters"}}） */
    fun openAiTools(): List<Map<String, Any>> = toolByName.values.map { t ->
        mapOf<String, Any>(
            "type" to "function",
            "function" to mapOf<String, Any>(
                "name" to t.name,
                "description" to t.description,
                "parameters" to t.inputSchema.ifEmpty { mapOf("type" to "object", "properties" to emptyMap<String, Any>()) },
            ),
        )
    }

    /** 调用工具。toolName 不存在或对应 server 已 dispose 时返回 isError=true 的结果（不抛）。 */
    suspend fun callTool(toolName: String, argsJson: String): Map<String, Any?> {
        val tool = toolByName[toolName] ?: return mapOf(
            "content" to "Error: tool \"$toolName\" not found",
            "isError" to true,
        )
        val service = services[tool.serverId] ?: return mapOf(
            "content" to "Error: server \"${tool.serverId}\" not connected",
            "isError" to true,
        )
        return try {
            service.callTool(toolName, argsJson)
        } catch (e: Exception) {
            mapOf("content" to "Error: ${e.message}", "isError" to true)
        }
    }

    fun warnings(): List<String> = warnings.toList()

    fun dispose() {
        for (s in services.values) {
            try {
                s.dispose()
            } catch (_: Exception) {}
        }
        services.clear()
        toolByName.clear()
        warnings.clear()
    }

    /**
     * 工具方法：从 mcpServersJson（JSON array）依次添加所有 server。容错：
     * 单条解析失败不影响其它 server。
     */
    suspend fun loadFromJson(mcpServersJson: String?, transport: String = "streamable_http") {
        if (mcpServersJson.isNullOrBlank()) return
        val arr = try {
            JSONArray(mcpServersJson)
        } catch (e: Exception) {
            warnings.add("invalid mcpServersJson: ${e.message}")
            return
        }
        for (i in 0 until arr.length()) {
            val obj = arr.optJSONObject(i) ?: continue
            addServer(obj, transport)
        }
    }
}
