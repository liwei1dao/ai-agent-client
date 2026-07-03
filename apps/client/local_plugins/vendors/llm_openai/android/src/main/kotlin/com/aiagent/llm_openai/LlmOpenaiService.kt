package com.aiagent.llm_openai

import android.util.Log
import com.aiagent.plugin_interface.LlmCallback
import com.aiagent.plugin_interface.NativeLlmService
import kotlinx.coroutines.*
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import kotlin.coroutines.coroutineContext

/**
 * LlmOpenaiService — OpenAI-compatible LLM 原生服务实现
 *
 * - OkHttp SSE 流式推理
 * - 文本 delta：实时通过 onFirstToken / onTextDelta 派发
 * - tool_calls delta：按 index 累积 id/name/arguments，流结束后一次性派发
 *   onToolCallStart(id, name) + onToolCallArguments(完整 arguments) + onDone(fullText)
 * - 取消机制（call.cancel()）
 */
class LlmOpenaiService : NativeLlmService {

    companion object {
        private const val TAG = "LlmOpenaiService"
    }

    private val client = OkHttpClient()
    @Volatile private var activeCall: Call? = null

    private var apiKey: String = ""
    private var baseUrl: String = ""
    private var model: String = ""
    private var temperature: Double = 0.7
    private var maxTokens: Int = 2048
    private var systemPrompt: String? = null

    override fun initialize(configJson: String) {
        val cfg = JSONObject(configJson)
        apiKey = cfg.optString("apiKey", "")
        baseUrl = cfg.optString("baseUrl", "").trimEnd('/')
        model = cfg.optString("model", "")
        temperature = cfg.optDouble("temperature", 0.7)
        maxTokens = cfg.optInt("maxTokens", 2048)
        systemPrompt = cfg.optString("systemPrompt", "").ifBlank { null }
        Log.d(TAG, "initialize: baseUrl=$baseUrl model=$model")
    }

    override suspend fun chat(
        requestId: String,
        messages: List<Map<String, Any>>,
        tools: List<Map<String, Any>>,
        callback: LlmCallback,
    ): String {
        if (apiKey.isBlank() || baseUrl.isBlank() || model.isBlank()) {
            val errMsg = "LLM config incomplete: apiKey=${apiKey.isNotBlank()} baseUrl=${baseUrl.isNotBlank()} model=${model.isNotBlank()}"
            Log.e(TAG, errMsg)
            callback.onError("config_error", errMsg)
            return ""
        }

        // Build request body
        val messagesArray = JSONArray()
        if (!systemPrompt.isNullOrBlank()) {
            messagesArray.put(JSONObject().apply {
                put("role", "system")
                put("content", systemPrompt)
            })
        }
        for (msg in messages) {
            messagesArray.put(JSONObject(msg))
        }

        val body = JSONObject().apply {
            put("model", model)
            put("stream", true)
            put("messages", messagesArray)
            if (temperature != 0.7) put("temperature", temperature)
            if (maxTokens != 2048) put("max_tokens", maxTokens)
            if (tools.isNotEmpty()) {
                put("tools", JSONArray(tools.map { JSONObject(it) }))
            }
        }

        val url = if (baseUrl.endsWith("/chat/completions")) baseUrl
                  else "$baseUrl/chat/completions"

        val request = Request.Builder()
            .url(url)
            .post(body.toString().toRequestBody("application/json".toMediaType()))
            .header("Authorization", "Bearer $apiKey")
            .build()

        Log.d(TAG, "POST $url model=$model messages=${messages.size} tools=${tools.size}")

        val fullText = StringBuilder()
        var isFirstToken = true
        // tool_calls 累积器（按 OpenAI delta 的 index 字段）
        val toolBuilders = mutableMapOf<Int, _ToolCallBuilder>()

        return try {
            val response = suspendableEnqueue(request) ?: return ""

            if (!response.isSuccessful) {
                val respBody = response.body?.string()?.take(300) ?: ""
                val errMsg = "HTTP ${response.code}: $respBody"
                Log.e(TAG, "LLM request failed: $errMsg")
                callback.onError("http_${response.code}", errMsg)
                return ""
            }

            val source = response.body?.source() ?: return ""
            while (!source.exhausted()) {
                if (!coroutineContext.isActive) break

                val line = source.readUtf8Line() ?: break
                if (!line.startsWith("data: ")) continue
                val data = line.removePrefix("data: ").trim()
                if (data == "[DONE]") break

                val parsed = parseDelta(data) ?: continue

                // 文本增量
                parsed.contentDelta?.takeIf { it.isNotEmpty() }?.let { delta ->
                    fullText.append(delta)
                    if (isFirstToken) {
                        isFirstToken = false
                        callback.onFirstToken(delta)
                    } else {
                        callback.onTextDelta(delta)
                    }
                }

                // tool_calls 增量按 index 累积
                for (tc in parsed.toolCallDeltas) {
                    val builder = toolBuilders.getOrPut(tc.index) { _ToolCallBuilder() }
                    if (tc.id != null) builder.id = tc.id
                    if (tc.name != null) builder.name = tc.name
                    if (tc.argumentsDelta != null) builder.arguments.append(tc.argumentsDelta)
                }
            }

            // 一次性派发累积完成的 tool_calls
            for (b in toolBuilders.values) {
                val name = b.name ?: continue
                if (name.isBlank()) continue
                callback.onToolCallStart(b.id ?: "", name)
                callback.onToolCallArguments(b.arguments.toString())
            }

            callback.onDone(fullText.toString())
            fullText.toString()

        } catch (e: CancellationException) {
            activeCall?.cancel()
            ""
        } catch (e: IOException) {
            Log.e(TAG, "IO error: ${e.message}")
            callback.onError("io_error", e.message ?: "Unknown IO error")
            ""
        }
    }

    override fun cancel() {
        activeCall?.cancel()
    }

    // ─────────────────────────────────────────────────
    // 内部
    // ─────────────────────────────────────────────────

    private suspend fun suspendableEnqueue(request: Request): Response? {
        return suspendCancellableCoroutine { cont ->
            val call = client.newCall(request)
            activeCall = call
            cont.invokeOnCancellation { call.cancel() }
            call.enqueue(object : Callback {
                override fun onResponse(call: Call, response: Response) {
                    if (cont.isActive) cont.resumeWith(Result.success(response))
                }
                override fun onFailure(call: Call, e: IOException) {
                    if (cont.isActive) cont.resumeWith(Result.failure(e))
                }
            })
        }
    }

    private fun parseDelta(json: String): _DeltaParsed? {
        return try {
            val obj = JSONObject(json)
            val choices = obj.optJSONArray("choices") ?: return null
            if (choices.length() == 0) return null
            val delta = choices.getJSONObject(0).optJSONObject("delta")
                ?: return _DeltaParsed(null, emptyList())

            val content = delta.optString("content", "").ifBlank { null }

            val toolDeltas = mutableListOf<_ToolCallDelta>()
            delta.optJSONArray("tool_calls")?.let { tcs ->
                for (i in 0 until tcs.length()) {
                    val tc = tcs.optJSONObject(i) ?: continue
                    val fn = tc.optJSONObject("function")
                    toolDeltas.add(
                        _ToolCallDelta(
                            index = tc.optInt("index", 0),
                            id = tc.optString("id", "").ifBlank { null },
                            name = fn?.optString("name", "")?.ifBlank { null },
                            argumentsDelta = fn?.optString("arguments", "")?.ifBlank { null },
                        )
                    )
                }
            }
            _DeltaParsed(content, toolDeltas)
        } catch (_: Exception) {
            null
        }
    }

    private data class _DeltaParsed(
        val contentDelta: String?,
        val toolCallDeltas: List<_ToolCallDelta>,
    )

    private data class _ToolCallDelta(
        val index: Int,
        val id: String?,
        val name: String?,
        val argumentsDelta: String?,
    )

    private class _ToolCallBuilder {
        var id: String? = null
        var name: String? = null
        val arguments = StringBuilder()
    }
}
