package com.aiagent.agent_runtime.pipeline

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
    private var activeCall: Call? = null

    /**
     * 执行 LLM 推理（挂起直到完成或取消）
     * @return 完整的 LLM 响应文本（用于 TTS）
     */
    suspend fun run(requestId: String, assistantMessageId: String, userText: String): String {
        val llmConfig = JSONObject(config.llmConfigJson)
        val apiKey = llmConfig.getString("apiKey")
        val baseUrl = llmConfig.getString("baseUrl").trimEnd('/')
        val model = llmConfig.getString("model")

        // 构建历史消息（从 DB 读取，最近 20 条）
        val history = db.messageDao().getMessages(config.agentId, 20)
            .reversed()
            .map { msg ->
                JSONObject().apply {
                    put("role", msg.role)
                    put("content", msg.content)
                }
            }

        val body = JSONObject().apply {
            put("model", model)
            put("stream", true)
            put("messages", JSONArray(history))
        }

        val request = Request.Builder()
            .url("$baseUrl/chat/completions")
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
                pushLlmEvent(requestId,
                    LlmEventData(sessionId, requestId, kind = "error",
                        errorCode = "http_${response.code}",
                        errorMessage = response.message))
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
