package com.aiagent.llm_volcengine

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
 * LlmVolcengineService — 火山引擎 Ark LLM 原生服务实现
 *
 * 走 ark 的 OpenAI 兼容接口：POST <baseUrl>/chat/completions (默认 baseUrl 写死为
 * https://ark.cn-beijing.volces.com/api/v3)；`model` 即接入点 ID（ep-xxx）。
 * 无 configJson / 空 baseUrl 时自动回退默认地址。
 */
class LlmVolcengineService : NativeLlmService {

    companion object {
        private const val TAG = "LlmVolcengineService"
        private const val DEFAULT_BASE_URL =
            "https://ark.cn-beijing.volces.com/api/v3"
    }

    private val client = OkHttpClient()
    @Volatile private var activeCall: Call? = null

    private var apiKey: String = ""
    private var baseUrl: String = DEFAULT_BASE_URL
    private var model: String = ""
    private var temperature: Double = 0.7
    private var maxTokens: Int = 2048
    private var systemPrompt: String? = null
    private var enableThinking: Boolean = false

    override fun initialize(configJson: String) {
        val cfg = JSONObject(configJson)
        apiKey = cfg.optString("apiKey", "")
        baseUrl = normalizeBaseUrl(cfg.optString("baseUrl", ""))
        model = cfg.optString("model", "")
        temperature = cfg.optDouble("temperature", 0.7)
        maxTokens = cfg.optInt("maxTokens", 2048)
        systemPrompt = cfg.optString("systemPrompt", "").ifBlank { null }
        enableThinking = cfg.optBoolean("enableThinking", false)
        Log.d(TAG, "initialize: baseUrl=$baseUrl model=$model thinking=$enableThinking")
    }

    override suspend fun chat(
        requestId: String,
        messages: List<Map<String, Any>>,
        tools: List<Map<String, Any>>,
        callback: LlmCallback,
    ): String {
        if (apiKey.isBlank() || model.isBlank()) {
            val errMsg = "LLM config incomplete: apiKey=${apiKey.isNotBlank()} model=${model.isNotBlank()}"
            Log.e(TAG, errMsg)
            callback.onError("config_error", errMsg)
            return ""
        }

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
            // 火山方舟 thinking 模型：默认关闭推理，避免首字延迟
            put("thinking", JSONObject().apply {
                put("type", if (enableThinking) "enabled" else "disabled")
            })
        }

        val url = "$baseUrl/chat/completions"

        val request = Request.Builder()
            .url(url)
            .post(body.toString().toRequestBody("application/json".toMediaType()))
            .header("Authorization", "Bearer $apiKey")
            .build()

        Log.d(TAG, "POST $url model=$model messages=${messages.size}")

        val fullText = StringBuilder()
        var isFirstToken = true

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
            // 跨 chunk 跟踪每个 tool_call 是否已经派发过 Start —— OpenAI 流式
            // 协议里同一 tool_call 通过 `index` 复用，第一帧带 id+name，后续
            // 帧只追加 arguments delta。
            val toolStarted = mutableMapOf<Int, Boolean>()

            while (!source.exhausted()) {
                if (!coroutineContext.isActive) break

                val line = source.readUtf8Line() ?: break
                if (!line.startsWith("data: ")) continue
                val data = line.removePrefix("data: ").trim()
                if (data == "[DONE]") break

                val chunk = parseDelta(data) ?: continue

                // 文本
                if (chunk.content.isNotEmpty()) {
                    fullText.append(chunk.content)
                    if (isFirstToken) {
                        isFirstToken = false
                        callback.onFirstToken(chunk.content)
                    } else {
                        callback.onTextDelta(chunk.content)
                    }
                }

                // 推理（doubao thinking 模型走 reasoning_content）
                if (chunk.thinking.isNotEmpty()) {
                    callback.onThinkingDelta(chunk.thinking)
                }

                // tool_calls：首帧带 id+name → onToolCallStart；
                // 后续帧只有 arguments delta → onToolCallArguments
                for (tc in chunk.toolCalls) {
                    val started = toolStarted[tc.index] == true
                    if (!started && !tc.id.isNullOrBlank() && !tc.name.isNullOrBlank()) {
                        callback.onToolCallStart(tc.id, tc.name)
                        toolStarted[tc.index] = true
                    }
                    if (tc.argsDelta.isNotEmpty()) {
                        callback.onToolCallArguments(tc.argsDelta)
                    }
                }
            }

            Log.d(TAG, "stream done: textLen=${fullText.length} toolCalls=${toolStarted.size}")
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

    private fun normalizeBaseUrl(raw: String): String {
        var u = raw.trim()
        if (u.isEmpty()) return DEFAULT_BASE_URL
        if (u.endsWith("/")) u = u.trimEnd('/')
        if (u.endsWith("/chat/completions")) {
            u = u.removeSuffix("/chat/completions")
        }
        return u
    }

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

    /**
     * 解析单帧 SSE delta。OpenAI 兼容格式：
     * - delta.content：文本增量
     * - delta.reasoning_content：思维链增量（doubao thinking 模型）
     * - delta.tool_calls[]：工具调用片段；首帧 `{index, id, function:{name, arguments:""}}`，
     *   后续帧 `{index, function:{arguments:"...delta..."}}`
     */
    private fun parseDelta(json: String): DeltaChunk? = try {
        val choice = JSONObject(json).getJSONArray("choices").getJSONObject(0)
        val delta = choice.optJSONObject("delta") ?: JSONObject()

        val content = delta.optString("content", "")
        val thinking = delta.optString("reasoning_content", "")

        val toolCalls = mutableListOf<ToolCallChunk>()
        delta.optJSONArray("tool_calls")?.let { arr ->
            for (i in 0 until arr.length()) {
                val tc = arr.optJSONObject(i) ?: continue
                val index = tc.optInt("index", i)
                val id = tc.optString("id", "").ifBlank { null }
                val func = tc.optJSONObject("function")
                val name = func?.optString("name", "")?.ifBlank { null }
                val args = func?.optString("arguments", "") ?: ""
                toolCalls.add(ToolCallChunk(index, id, name, args))
            }
        }

        DeltaChunk(content, thinking, toolCalls)
    } catch (_: Exception) {
        null
    }

    private data class DeltaChunk(
        val content: String,
        val thinking: String,
        val toolCalls: List<ToolCallChunk>,
    )

    private data class ToolCallChunk(
        val index: Int,
        val id: String?,
        val name: String?,
        val argsDelta: String,
    )
}
