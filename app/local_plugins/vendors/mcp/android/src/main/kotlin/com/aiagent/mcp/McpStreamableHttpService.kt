package com.aiagent.mcp

import android.util.Log
import com.aiagent.plugin_interface.NativeMcpService
import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.TimeUnit

/**
 * McpStreamableHttpService — MCP Streamable HTTP transport（MCP 2024-11-05）
 *
 * 协议：单一 endpoint，POST 发 JSON-RPC 2.0；响应 Content-Type 为
 * `application/json` 或 `text/event-stream`，后者按 SSE 取首个 `data:` 帧。
 * 服务器会在 `initialize` 响应中下发 `Mcp-Session-Id`，后续请求必须回带。
 *
 * 单实例对应单 server。多 server 由 `McpRouter` 聚合。
 */
class McpStreamableHttpService : NativeMcpService {

    companion object {
        private const val TAG = "McpStreamableHttp"
        private const val PROTOCOL_VERSION = "2024-11-05"
        private val JSON_MEDIA = "application/json".toMediaType()
    }

    @Volatile private var client: OkHttpClient? = null
    private var url: String = ""
    private var authHeader: String? = null
    private val extraHeaders = mutableMapOf<String, String>()
    private var enabledTools: Set<String> = emptySet()
    private var serverId: String = ""

    @Volatile private var sessionId: String? = null
    @Volatile private var initialized: Boolean = false
    @Volatile private var rpcId: Int = 0

    // ─────────────────────────────────────────────────
    // NativeMcpService
    // ─────────────────────────────────────────────────

    override suspend fun initialize(configJson: String) {
        dispose()

        val cfg = JSONObject(configJson)
        serverId = cfg.optString("id", "")
        url = cfg.optString("url", "").also {
            require(it.isNotBlank()) { "McpServerConfig.url required" }
        }
        authHeader = cfg.optString("authHeader", "").ifBlank { null }
        val timeoutSec = cfg.optInt("timeoutSeconds", 30).coerceAtLeast(1)

        enabledTools = cfg.optJSONArray("enabledTools")?.let { arr ->
            buildSet {
                for (i in 0 until arr.length()) add(arr.optString(i))
            }
        } ?: emptySet()

        cfg.optJSONObject("extraHeaders")?.let { extras ->
            for (k in extras.keys()) extraHeaders[k] = extras.optString(k, "")
        }

        client = OkHttpClient.Builder()
            .connectTimeout(timeoutSec.toLong(), TimeUnit.SECONDS)
            .readTimeout(timeoutSec.toLong(), TimeUnit.SECONDS)
            .writeTimeout(timeoutSec.toLong(), TimeUnit.SECONDS)
            .build()

        // JSON-RPC initialize 握手
        val initParams = JSONObject().apply {
            put("protocolVersion", PROTOCOL_VERSION)
            put("capabilities", JSONObject().apply { put("tools", JSONObject()) })
            put("clientInfo", JSONObject().apply {
                put("name", "ai-agent-client")
                put("version", "1.0.0")
            })
        }
        val initResult = rpc("initialize", initParams)
        if (!initResult.has("protocolVersion") && !initResult.has("serverInfo")) {
            throw IllegalStateException("mcp.handshake_failed: initialize 响应缺少 protocolVersion / serverInfo")
        }
        rpcNotification("notifications/initialized", JSONObject())
        initialized = true
        Log.d(TAG, "Initialized server: $serverId @ $url")
    }

    override suspend fun listTools(): List<Map<String, Any?>> {
        ensureReady()
        val result = rpc("tools/list", JSONObject())
        val arr = result.optJSONArray("tools") ?: return emptyList()
        val out = mutableListOf<Map<String, Any?>>()
        for (i in 0 until arr.length()) {
            val t = arr.optJSONObject(i) ?: continue
            val name = t.optString("name", "")
            if (name.isBlank()) continue
            if (enabledTools.isNotEmpty() && name !in enabledTools) continue
            val schema = t.optJSONObject("inputSchema")?.let { jsonObjectToMap(it) } ?: emptyMap<String, Any?>()
            out.add(
                mapOf(
                    "name" to name,
                    "description" to t.optString("description", ""),
                    "inputSchema" to schema,
                    "serverId" to serverId,
                )
            )
        }
        return out
    }

    override suspend fun callTool(toolName: String, argsJson: String): Map<String, Any?> {
        ensureReady()
        val argsObj = if (argsJson.isBlank()) JSONObject() else try {
            JSONObject(argsJson)
        } catch (_: Exception) {
            JSONObject()
        }
        val params = JSONObject().apply {
            put("name", toolName)
            put("arguments", argsObj)
        }
        val result = rpc("tools/call", params)
        val isError = result.optBoolean("isError", false)
        val contentArr = result.optJSONArray("content")
        val sb = StringBuilder()
        if (contentArr != null) {
            for (i in 0 until contentArr.length()) {
                val c = contentArr.optJSONObject(i) ?: continue
                if (c.optString("type") == "text") {
                    val txt = c.optString("text", "")
                    if (txt.isNotEmpty()) {
                        if (sb.isNotEmpty()) sb.append("\n")
                        sb.append(txt)
                    }
                }
            }
        }
        return mapOf("content" to sb.toString(), "isError" to isError)
    }

    override fun dispose() {
        client = null
        sessionId = null
        initialized = false
        rpcId = 0
        enabledTools = emptySet()
        extraHeaders.clear()
        authHeader = null
    }

    // ─────────────────────────────────────────────────
    // 内部
    // ─────────────────────────────────────────────────

    private fun ensureReady() {
        check(client != null) { "McpStreamableHttpService disposed" }
        check(initialized) { "McpStreamableHttpService not initialized — call initialize() first" }
    }

    private fun buildHeaders(builder: Request.Builder): Request.Builder {
        builder.header("Content-Type", "application/json")
        builder.header("Accept", "application/json, text/event-stream")
        authHeader?.takeIf { it.isNotBlank() }?.let { builder.header("Authorization", it) }
        sessionId?.takeIf { it.isNotBlank() }?.let { builder.header("Mcp-Session-Id", it) }
        for ((k, v) in extraHeaders) builder.header(k, v)
        return builder
    }

    private suspend fun rpc(method: String, params: JSONObject): JSONObject {
        rpcId += 1
        val body = JSONObject().apply {
            put("jsonrpc", "2.0")
            put("id", rpcId)
            put("method", method)
            put("params", params)
        }
        val resp = postWithBody(body)
        if (resp.statusCode != 200 && resp.statusCode != 202) {
            throw IllegalStateException("mcp.http_${resp.statusCode}: ${resp.bodySnippet()}")
        }
        val rpcObj = parseRpcBody(resp)
        rpcObj.optJSONObject("error")?.let { err ->
            throw IllegalStateException("mcp.rpc_${err.optInt("code")}: ${err.optString("message")}")
        }
        return rpcObj.optJSONObject("result") ?: JSONObject()
    }

    private suspend fun rpcNotification(method: String, params: JSONObject) {
        val body = JSONObject().apply {
            put("jsonrpc", "2.0")
            put("method", method)
            put("params", params)
        }
        val resp = postWithBody(body)
        if (resp.statusCode >= 400) {
            throw IllegalStateException("mcp.http_${resp.statusCode}: ${resp.bodySnippet()}")
        }
    }

    private suspend fun postWithBody(body: JSONObject): _RpcResponse {
        val req = Request.Builder().url(url).also { buildHeaders(it) }
            .post(body.toString().toRequestBody(JSON_MEDIA))
            .build()
        val response = enqueue(req)
        try {
            response.header("Mcp-Session-Id")?.takeIf { it.isNotBlank() }?.let { sessionId = it }
            val ct = response.header("Content-Type") ?: ""
            val text = response.body?.string() ?: ""
            return _RpcResponse(response.code, ct, text)
        } finally {
            response.close()
        }
    }

    private suspend fun enqueue(request: Request): Response {
        val c = client ?: throw IllegalStateException("McpStreamableHttpService disposed")
        return suspendCancellableCoroutine { cont ->
            val call = c.newCall(request)
            cont.invokeOnCancellation { call.cancel() }
            call.enqueue(object : Callback {
                override fun onResponse(call: Call, response: Response) {
                    if (cont.isActive) cont.resumeWith(Result.success(response))
                    else response.close()
                }
                override fun onFailure(call: Call, e: IOException) {
                    if (cont.isActive) cont.resumeWith(Result.failure(e))
                }
            })
        }
    }

    private fun parseRpcBody(resp: _RpcResponse): JSONObject {
        if (resp.contentType.contains("text/event-stream", ignoreCase = true)) {
            for (raw in resp.body.split('\n')) {
                val line = raw.trimEnd()
                if (line.startsWith("data:")) {
                    val payload = line.substring(5).trimStart()
                    if (payload.isEmpty()) continue
                    return JSONObject(payload)
                }
            }
            throw IllegalStateException("mcp.invalid_response: SSE 响应未包含 JSON-RPC data 帧")
        }
        if (resp.body.isBlank()) return JSONObject()
        return JSONObject(resp.body)
    }

    private fun jsonObjectToMap(obj: JSONObject): Map<String, Any?> {
        val out = mutableMapOf<String, Any?>()
        for (k in obj.keys()) out[k] = jsonValueToAny(obj.get(k))
        return out
    }

    private fun jsonArrayToList(arr: JSONArray): List<Any?> {
        val out = mutableListOf<Any?>()
        for (i in 0 until arr.length()) out.add(jsonValueToAny(arr.get(i)))
        return out
    }

    private fun jsonValueToAny(v: Any?): Any? = when (v) {
        is JSONObject -> jsonObjectToMap(v)
        is JSONArray -> jsonArrayToList(v)
        JSONObject.NULL -> null
        else -> v
    }

    private data class _RpcResponse(val statusCode: Int, val contentType: String, val body: String) {
        fun bodySnippet(): String = if (body.length > 200) body.substring(0, 200) + "…" else body
    }
}
