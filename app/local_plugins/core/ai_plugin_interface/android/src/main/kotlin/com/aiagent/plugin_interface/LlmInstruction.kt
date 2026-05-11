package com.aiagent.plugin_interface

import org.json.JSONArray
import org.json.JSONObject

/**
 * 用户在 LLM 服务配置界面登记的"指令"占位。
 *
 * 不携带任何实际执行逻辑——只是一个 LLM 可见的 function 名 + 描述（+ 可选 JSON Schema）。
 * 触发后由调度层（ChatAgentSession 等）派发 instructionTriggered 事件；
 * 真正的副作用由 [InstructionHandlerRegistry] 中注册的处理器完成。
 *
 * 持久化形态：随 llmConfigJson 一起携带，键名 "instructions"，值为数组：
 *   [
 *     { "name": "media.next_track", "description": "切换下一曲" },
 *     { "name": "lights.toggle", "description": "灯光开关", "parameters": {...} }
 *   ]
 */
data class LlmInstructionDef(
    val name: String,
    val description: String,
    /** 可选 JSON Schema；为 null 时视为无参函数。 */
    val parameters: Map<String, Any?>? = null,
) {
    /** 转为 OpenAI function tool 描述（与 NativeMcpRouter.openAiTools() 同型）。 */
    fun toOpenAiTool(): Map<String, Any> = mapOf(
        "type" to "function",
        "function" to mapOf<String, Any>(
            "name" to name,
            "description" to description,
            "parameters" to (parameters ?: mapOf(
                "type" to "object",
                "properties" to emptyMap<String, Any>(),
            )),
        ),
    )

    companion object {
        /**
         * 从 llmConfigJson 顶层解析 `instructions` 数组。容错：
         * - 整体不是合法 JSON → 返回空列表
         * - 单条字段缺失 → 跳过该条
         */
        fun listFromLlmConfigJson(llmConfigJson: String?): List<LlmInstructionDef> {
            if (llmConfigJson.isNullOrBlank()) return emptyList()
            return try {
                val root = JSONObject(llmConfigJson)
                val arr = root.optJSONArray("instructions") ?: return emptyList()
                val out = mutableListOf<LlmInstructionDef>()
                for (i in 0 until arr.length()) {
                    val obj = arr.optJSONObject(i) ?: continue
                    val name = obj.optString("name", "").trim()
                    if (name.isEmpty()) continue
                    val params = obj.opt("parameters")
                    val parameters: Map<String, Any?>? = when (params) {
                        is JSONObject -> params.toMap()
                        else -> null
                    }
                    out.add(
                        LlmInstructionDef(
                            name = name,
                            description = obj.optString("description", ""),
                            parameters = parameters,
                        )
                    )
                }
                out
            } catch (_: Exception) {
                emptyList()
            }
        }

        private fun JSONObject.toMap(): Map<String, Any?> {
            val m = mutableMapOf<String, Any?>()
            val it = keys()
            while (it.hasNext()) {
                val k = it.next()
                m[k] = when (val v = opt(k)) {
                    is JSONObject -> v.toMap()
                    is JSONArray -> v.toList()
                    JSONObject.NULL -> null
                    else -> v
                }
            }
            return m
        }

        private fun JSONArray.toList(): List<Any?> {
            val out = mutableListOf<Any?>()
            for (i in 0 until length()) {
                out.add(
                    when (val v = opt(i)) {
                        is JSONObject -> v.toMap()
                        is JSONArray -> v.toList()
                        JSONObject.NULL -> null
                        else -> v
                    }
                )
            }
            return out
        }
    }
}

/**
 * 指令处理器签名：拿到解析后的参数（JSON string），返回 LLM 期望的"调用结果"字符串。
 * 返回 null 表示用户没注册副作用，调度层会回填一段默认 ok 文本给 LLM 让对话能继续。
 */
typealias InstructionHandler = suspend (name: String, argsJson: String) -> String?

/**
 * 全局指令处理器注册表。
 *
 * 调度层（ChatAgentSession 等）会在派发 instructionTriggered 事件之后尝试同名 handler；
 * 底层 agent 对象只需在 app 启动期间
 * `InstructionHandlerRegistry.register("media.next_track", ...)` 即可挂逻辑。
 */
object InstructionHandlerRegistry {
    private val handlers = mutableMapOf<String, InstructionHandler>()

    @Synchronized
    fun register(name: String, handler: InstructionHandler) {
        handlers[name] = handler
    }

    @Synchronized
    fun unregister(name: String) {
        handlers.remove(name)
    }

    @Synchronized
    fun has(name: String): Boolean = handlers.containsKey(name)

    /** 找到对应 handler 并执行。无匹配时返回 null。异常时回填错误字符串。 */
    suspend fun dispatch(name: String, argsJson: String): String? {
        val h = synchronized(this) { handlers[name] } ?: return null
        return try {
            h(name, argsJson)
        } catch (e: Throwable) {
            "Error: ${e.message}"
        }
    }
}
