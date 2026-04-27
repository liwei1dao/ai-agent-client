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
            while (!source.exhausted()) {
                if (!coroutineContext.isActive) break

                val line = source.readUtf8Line() ?: break
                if (!line.startsWith("data: ")) continue
                val data = line.removePrefix("data: ").trim()
                if (data == "[DONE]") break

                val delta = parseTextDelta(data) ?: continue
                if (delta.isEmpty()) continue

                fullText.append(delta)

                if (isFirstToken) {
                    isFirstToken = false
                    callback.onFirstToken(delta)
                } else {
                    callback.onTextDelta(delta)
                }
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

    private fun parseTextDelta(json: String): String? = try {
        JSONObject(json)
            .getJSONArray("choices")
            .getJSONObject(0)
            .getJSONObject("delta")
            .optString("content", "")
    } catch (_: Exception) { null }
}
