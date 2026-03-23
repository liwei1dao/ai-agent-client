package com.aiagent.local_db

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import com.aiagent.local_db.entity.*

class LocalDbPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private lateinit var db: AppDatabase
    private lateinit var channel: MethodChannel

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        db = AppDatabase.getInstance(binding.applicationContext)
        channel = MethodChannel(binding.binaryMessenger, "local_db/commands")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        scope.cancel()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        scope.launch {
            try {
                val value = when (call.method) {
                    // ── ServiceConfig ──────────────────────────────────────
                    "upsertServiceConfig" -> {
                        val args = call.arguments as Map<*, *>
                        db.serviceConfigDao().upsert(
                            ServiceConfigEntity(
                                id = args["id"] as String,
                                type = args["type"] as String,
                                vendor = args["vendor"] as String,
                                name = args["name"] as String,
                                configJson = args["configJson"] as String,
                                createdAt = (args["createdAt"] as Number).toLong(),
                            )
                        )
                        null
                    }
                    "deleteServiceConfig" -> {
                        val args = call.arguments as Map<*, *>
                        db.serviceConfigDao().delete(args["id"] as String)
                        null
                    }
                    "getAllServiceConfigs" -> {
                        db.serviceConfigDao().getAll().map { e ->
                            mapOf(
                                "id" to e.id, "type" to e.type, "vendor" to e.vendor,
                                "name" to e.name, "configJson" to e.configJson,
                                "createdAt" to e.createdAt,
                            )
                        }
                    }

                    // ── Agent ──────────────────────────────────────────────
                    "upsertAgent" -> {
                        val args = call.arguments as Map<*, *>
                        db.agentDao().upsert(
                            AgentEntity(
                                id = args["id"] as String,
                                name = args["name"] as String,
                                type = args["type"] as String,
                                configJson = args["configJson"] as String,
                                createdAt = (args["createdAt"] as Number).toLong(),
                                updatedAt = (args["updatedAt"] as Number).toLong(),
                            )
                        )
                        null
                    }
                    "deleteAgent" -> {
                        val args = call.arguments as Map<*, *>
                        db.agentDao().delete(args["id"] as String)
                        null
                    }
                    "getAllAgents" -> {
                        db.agentDao().getAll().map { e ->
                            mapOf(
                                "id" to e.id, "name" to e.name, "type" to e.type,
                                "configJson" to e.configJson,
                                "createdAt" to e.createdAt, "updatedAt" to e.updatedAt,
                            )
                        }
                    }

                    // ── Message ────────────────────────────────────────────
                    "getMessages" -> {
                        val args = call.arguments as Map<*, *>
                        val agentId = args["agentId"] as String
                        val limit = (args["limit"] as Number).toInt()
                        db.messageDao().getMessages(agentId, limit).map { e ->
                            mapOf(
                                "id" to e.id, "agentId" to e.agentId, "role" to e.role,
                                "content" to e.content, "status" to e.status,
                                "createdAt" to e.createdAt, "updatedAt" to e.updatedAt,
                            )
                        }
                    }

                    "deleteMessages" -> {
                        val args = call.arguments as Map<*, *>
                        db.messageDao().deleteByAgent(args["agentId"] as String)
                        null
                    }

                    // ── McpServer ──────────────────────────────────────────
                    "upsertMcpServer" -> {
                        val args = call.arguments as Map<*, *>
                        db.mcpServerDao().upsert(
                            McpServerEntity(
                                id = args["id"] as String,
                                agentId = args["agentId"] as String,
                                name = args["name"] as String,
                                url = args["url"] as String,
                                transport = args["transport"] as String,
                                authHeader = args["authHeader"] as String?,
                                enabledToolsJson = args["enabledToolsJson"] as String,
                                isEnabled = args["isEnabled"] as Boolean,
                                createdAt = (args["createdAt"] as Number).toLong(),
                            )
                        )
                        null
                    }
                    "deleteMcpServer" -> {
                        val args = call.arguments as Map<*, *>
                        db.mcpServerDao().delete(args["id"] as String)
                        null
                    }
                    "getMcpServersByAgent" -> {
                        val args = call.arguments as Map<*, *>
                        db.mcpServerDao().getByAgent(args["agentId"] as String).map { e ->
                            mapOf(
                                "id" to e.id, "agentId" to e.agentId, "name" to e.name,
                                "url" to e.url, "transport" to e.transport,
                                "authHeader" to e.authHeader,
                                "enabledToolsJson" to e.enabledToolsJson,
                                "isEnabled" to e.isEnabled, "createdAt" to e.createdAt,
                            )
                        }
                    }

                    else -> {
                        withContext(Dispatchers.Main) { result.notImplemented() }
                        return@launch
                    }
                }
                withContext(Dispatchers.Main) { result.success(value) }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("DB_ERROR", e.message, null)
                }
            }
        }
    }
}

// ── Data classes (kept for reference, not used by MethodChannel handler) ──

data class ServiceConfigRow(
    val id: String, val type: String, val vendor: String,
    val name: String, val configJson: String, val createdAt: Long,
)

data class AgentRow(
    val id: String, val name: String, val type: String,
    val configJson: String, val createdAt: Long, val updatedAt: Long,
)

data class MessageRow(
    val id: String, val agentId: String, val role: String,
    val content: String, val status: String,
    val createdAt: Long, val updatedAt: Long,
)

data class McpServerRow(
    val id: String, val agentId: String, val name: String,
    val url: String, val transport: String, val authHeader: String?,
    val enabledToolsJson: String, val isEnabled: Boolean, val createdAt: Long,
)
