package com.aiagent.plugin_interface

import android.util.Log
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject
import java.security.MessageDigest

/**
 * 进程级 MCP service + tool list 缓存（单例）。
 *
 * 设计动机：每次 ChatAgentSession 创建都重复做 HTTP `initialize` 握手 +
 * `tools/list`，多 agent 同时绑同一 MCP server 时尤其浪费。MCP 工具列表
 * 是 server 端状态，正常情况下进程生命周期内不变，启动一次缓存即可。
 *
 * 行为：
 * - 按 `serverId` 索引；同 id 配置（fingerprint）变更时丢弃旧 entry 重建
 * - `getOrInit` 串行化（mutex），并发同 id 首启不会重复握手
 * - 单 server 内部失败由调用方处理；本类只保证"成功 init 就缓存"
 * - 缓存条目永不主动过期；显式 `evict(id)` / `evictAll()` 用于"用户改配置"
 */
object NativeMcpServiceCache {

    private const val TAG = "McpServiceCache"

    data class Entry(
        val service: NativeMcpService,
        val tools: List<Map<String, Any?>>,
        val fingerprint: String,
        val transport: String,
    )

    private val mutex = Mutex()
    private val entries = mutableMapOf<String, Entry>()

    /**
     * 取 server 的 (service, tools)，没缓存或 fingerprint 变了就 init。
     * 失败抛异常，由调用方记 warning，不污染缓存。
     */
    suspend fun getOrInit(
        serverConfig: JSONObject,
        transport: String,
    ): Entry = mutex.withLock {
        val id = serverConfig.optString("id", "")
        require(id.isNotBlank()) { "serverConfig.id required" }

        val fingerprint = fingerprint(serverConfig, transport)
        entries[id]?.let { existing ->
            if (existing.fingerprint == fingerprint && existing.transport == transport) {
                return@withLock existing
            }
            // 配置变了 → 释放旧的
            Log.d(TAG, "evict $id: config changed")
            runCatching { existing.service.dispose() }
            entries.remove(id)
        }

        val service = NativeServiceRegistry.createMcp(transport)
        try {
            service.initialize(serverConfig.toString())
            val tools = service.listTools()
            val entry = Entry(service, tools, fingerprint, transport)
            entries[id] = entry
            Log.d(TAG, "cached $id: ${tools.size} tools")
            entry
        } catch (e: Exception) {
            runCatching { service.dispose() }
            throw e
        }
    }

    /** 用户在 UI 改了某个 MCP server 配置时调用。下次 getOrInit 会重建。 */
    suspend fun evict(serverId: String) = mutex.withLock {
        entries.remove(serverId)?.let { runCatching { it.service.dispose() } }
    }

    suspend fun evictAll() = mutex.withLock {
        for (e in entries.values) runCatching { e.service.dispose() }
        entries.clear()
    }

    /**
     * fingerprint：取配置中影响连接 + 工具暴露的字段做 sha256。
     * 不含 `name`（仅展示用）。`enabledTools` 排序后再 hash 保证稳定。
     */
    private fun fingerprint(cfg: JSONObject, transport: String): String {
        val sb = StringBuilder()
        sb.append("transport=").append(transport).append('\n')
        sb.append("url=").append(cfg.optString("url", "")).append('\n')
        sb.append("authHeader=").append(cfg.optString("authHeader", "")).append('\n')
        sb.append("timeoutSeconds=").append(cfg.optInt("timeoutSeconds", 30)).append('\n')
        cfg.optJSONArray("enabledTools")?.let { arr ->
            val list = mutableListOf<String>()
            for (i in 0 until arr.length()) list.add(arr.optString(i))
            list.sort()
            sb.append("enabledTools=").append(list.joinToString(",")).append('\n')
        }
        cfg.optJSONObject("extraHeaders")?.let { extras ->
            val keys = extras.keys().asSequence().toList().sorted()
            for (k in keys) sb.append("h.").append(k).append('=').append(extras.optString(k, "")).append('\n')
        }
        val md = MessageDigest.getInstance("SHA-256").digest(sb.toString().toByteArray())
        return md.joinToString("") { "%02x".format(it) }
    }
}
