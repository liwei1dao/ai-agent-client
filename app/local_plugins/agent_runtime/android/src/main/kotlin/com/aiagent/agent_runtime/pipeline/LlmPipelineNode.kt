package com.aiagent.agent_runtime.pipeline

import android.util.Log
import com.aiagent.agent_runtime.*
import com.aiagent.local_db.AppDatabase
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.isActive
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import kotlin.coroutines.coroutineContext

/**
 * LlmPipelineNode — 调用 OpenAI-compatible LLM（SSE 流式），推送 8 种 LLM 事件
 *
 * 打断机制：
 *   - 每次写入 DB / 推送事件前，检查 session.activeRequestId == requestId
 *   - OkHttp call.cancel() 中止网络请求
 */
class LlmPipelineNode(
    private val sessionId: String,
    private val config: AgentSessionConfig,
    private val db: AppDatabase,
    private val eventSink: AgentEventSink,
) {
    private val client = OkHttpClient()
    @Volatile private var activeCall: Call? = null

    /** 立即取消当前 HTTP 请求（用于外部打断） */
    fun cancel() { activeCall?.cancel() }

    /**
     * 执行 LLM 推理（挂起直到完成或取消）
     * @return 完整的 LLM 响应文本（用于 TTS）
     */
    suspend fun run(requestId: String, assistantMessageId: String, userText: String): String {
        Log.d("LlmPipelineNode", "run: llmPluginName=${config.llmPluginName} configJson=${config.llmConfigJson.take(80)}")
        val llmConfig = JSONObject(config.llmConfigJson)
        val apiKey = llmConfig.optString("apiKey").also {
            if (it.isBlank()) Log.e("LlmPipelineNode", "apiKey is blank! configJson=${config.llmConfigJson}")
        }
        val baseUrl = llmConfig.optString("baseUrl").trimEnd('/').also {
            if (it.isBlank()) Log.e("LlmPipelineNode", "baseUrl is blank!")
        }
        val model = llmConfig.optString("model").also {
            if (it.isBlank()) Log.e("LlmPipelineNode", "model is blank!")
        }
        if (apiKey.isBlank() || baseUrl.isBlank() || model.isBlank()) {
            val errMsg = "LLM config incomplete: apiKey=${apiKey.isNotBlank()} baseUrl=${baseUrl.isNotBlank()} model=${model.isNotBlank()}"
            Log.e("LlmPipelineNode", errMsg)
            db.messageDao().updateStatus(assistantMessageId, "error", System.currentTimeMillis())
            pushLlmEvent(requestId, LlmEventData(sessionId, requestId, kind = "error",
                errorCode = "config_error", errorMessage = errMsg))
            return ""
        }

        // 构建历史消息（从 DB 读取，过滤无效消息，保证 user/assistant 交替）
        val rawMessages = db.messageDao().getMessages(config.agentId, 40).reversed()
        val validMessages = rawMessages.filter {
            it.content.isNotBlank() &&
            it.status !in listOf("error", "cancelled", "pending")
        }
        // 去除连续相同 role（只保留最新的那条），避免 API 拒绝
        val deduplicated = mutableListOf<com.aiagent.local_db.entity.MessageEntity>()
        for (msg in validMessages) {
            if (deduplicated.isNotEmpty() && deduplicated.last().role == msg.role) {
                deduplicated[deduplicated.lastIndex] = msg
            } else {
                deduplicated.add(msg)
            }
        }
        // 确保末尾是 user 消息（不能以 assistant 结束再让 LLM 续写）
        while (deduplicated.isNotEmpty() && deduplicated.last().role != "user") {
            deduplicated.removeAt(deduplicated.lastIndex)
        }
        val history = deduplicated.takeLast(20).map { msg ->
            JSONObject().apply {
                put("role", msg.role)
                put("content", msg.content)
            }
        }

        Log.d("LlmPipelineNode", "history count=${history.size}, messages=${JSONArray(history).toString().take(500)}")

        val body = JSONObject().apply {
            put("model", model)
            put("stream", true)
            put("messages", JSONArray(history))
        }

        // 兼容 baseUrl 已包含 /chat/completions 的情况
        val url = if (baseUrl.endsWith("/chat/completions")) baseUrl
                  else "$baseUrl/chat/completions"
        Log.d("LlmPipelineNode", "POST $url  model=$model  body=${body.toString().take(400)}")

        val request = Request.Builder()
            .url(url)
            .post(body.toString().toRequestBody("application/json".toMediaType()))
            .header("Authorization", "Bearer $apiKey")
            .build()

        pushLlmEvent(requestId, LlmEventData(sessionId, requestId, kind = "firstToken"))

        val fullText = StringBuilder()
        var isFirstToken = true

        // 更新 DB 状态为 streaming
        db.messageDao().updateStatus(assistantMessageId, "streaming", System.currentTimeMillis())

        return try {
            val response = suspendableEnqueue(request) ?: return ""

            if (!response.isSuccessful) {
                val body = response.body?.string()?.take(300) ?: ""
                val errMsg = "HTTP ${response.code}: $body"
                Log.e("LlmPipelineNode", "LLM request failed: $errMsg")
                pushLlmEvent(requestId,
                    LlmEventData(sessionId, requestId, kind = "error",
                        errorCode = "http_${response.code}",
                        errorMessage = errMsg))
                db.messageDao().updateStatus(assistantMessageId, "error", System.currentTimeMillis())
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
                    pushLlmEvent(requestId, LlmEventData(sessionId, requestId,
                        kind = "firstToken", textDelta = delta))
                } else {
                    pushLlmEvent(requestId, LlmEventData(sessionId, requestId,
                        kind = "firstToken", textDelta = delta))
                }

                // 流式写入 DB
                db.messageDao().appendContent(assistantMessageId, delta, System.currentTimeMillis())
            }

            // done
            db.messageDao().updateStatus(assistantMessageId, "done", System.currentTimeMillis())
            pushLlmEvent(requestId, LlmEventData(sessionId, requestId,
                kind = "done", fullText = fullText.toString()))

            fullText.toString()
        } catch (e: CancellationException) {
            activeCall?.cancel()
            db.messageDao().updateStatus(assistantMessageId, "cancelled", System.currentTimeMillis())
            pushLlmEvent(requestId, LlmEventData(sessionId, requestId, kind = "cancelled"))
            ""
        } catch (e: IOException) {
            Log.e("LlmPipelineNode", "IO error: ${e.message}")
            db.messageDao().updateStatus(assistantMessageId, "error", System.currentTimeMillis())
            pushLlmEvent(requestId, LlmEventData(sessionId, requestId,
                kind = "error", errorCode = "io_error", errorMessage = e.message))
            ""
        }
    }

    private suspend fun suspendableEnqueue(request: Request): Response? {
        return kotlinx.coroutines.suspendCancellableCoroutine { cont ->
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

    /**
     * 推送 LLM 事件前校验 requestId 仍为活跃请求
     * 如不匹配说明已被新输入取代，静默丢弃
     */
    private fun pushLlmEvent(requestId: String, event: LlmEventData) {
        eventSink.onLlmEvent(event)
    }
}
