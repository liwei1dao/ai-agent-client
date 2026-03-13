package com.aiagent.local_db

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import com.aiagent.local_db.entity.*

/**
 * LocalDbPlugin — Flutter Plugin 入口
 *
 * Pigeon 生成的 LocalDbApi 接口由本类实现。
 * 所有 DB 操作运行在 IO 协程，结果切回主线程返回给 Pigeon。
 *
 * 注意：Pigeon 生成代码（LocalDbApi.g.kt）在运行 pigeon 后自动生成，
 * 此处手写的 setup() 调用将在生成后补充。
 */
class LocalDbPlugin : FlutterPlugin {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private lateinit var db: AppDatabase

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        db = AppDatabase.getInstance(binding.applicationContext)
        // TODO: LocalDbApi.setUp(binding.binaryMessenger, LocalDbApiImpl(db, scope))
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        scope.cancel()
    }
}

/**
 * LocalDbApiImpl — 实现 Pigeon 生成的 LocalDbApi 接口。
 * 此类在 Pigeon 代码生成后实现具体接口方法。
 */
class LocalDbApiImpl(
    private val db: AppDatabase,
    private val scope: CoroutineScope,
) {
    // ── ServiceConfig ──────────────────────────────────────────────────────

    fun upsertServiceConfig(row: ServiceConfigRow, callback: (Result<Unit>) -> Unit) {
        scope.launch {
            try {
                db.serviceConfigDao().upsert(
                    ServiceConfigEntity(
                        id = row.id,
                        type = row.type,
                        vendor = row.vendor,
                        name = row.name,
                        configJson = row.configJson,
                        createdAt = row.createdAt,
                    )
                )
                withContext(Dispatchers.Main) { callback(Result.success(Unit)) }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) { callback(Result.failure(e)) }
            }
        }
    }

    fun deleteServiceConfig(id: String, callback: (Result<Unit>) -> Unit) {
        scope.launch {
            runCatching { db.serviceConfigDao().delete(id) }
                .let { withContext(Dispatchers.Main) { callback(it) } }
        }
    }

    fun getAllServiceConfigs(callback: (Result<List<ServiceConfigRow>>) -> Unit) {
        scope.launch {
            try {
                val rows = db.serviceConfigDao().getAll().map { e ->
                    ServiceConfigRow(
                        id = e.id,
                        type = e.type,
                        vendor = e.vendor,
                        name = e.name,
                        configJson = e.configJson,
                        createdAt = e.createdAt,
                    )
                }
                withContext(Dispatchers.Main) { callback(Result.success(rows)) }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) { callback(Result.failure(e)) }
            }
        }
    }

    // ── Agent ──────────────────────────────────────────────────────────────

    fun upsertAgent(row: AgentRow, callback: (Result<Unit>) -> Unit) {
        scope.launch {
            runCatching {
                db.agentDao().upsert(
                    AgentEntity(
                        id = row.id,
                        name = row.name,
                        type = row.type,
                        configJson = row.configJson,
                        createdAt = row.createdAt,
                        updatedAt = row.updatedAt,
                    )
                )
            }.let { withContext(Dispatchers.Main) { callback(it) } }
        }
    }

    fun deleteAgent(id: String, callback: (Result<Unit>) -> Unit) {
        scope.launch {
            runCatching { db.agentDao().delete(id) }
                .let { withContext(Dispatchers.Main) { callback(it) } }
        }
    }

    fun getAllAgents(callback: (Result<List<AgentRow>>) -> Unit) {
        scope.launch {
            try {
                val rows = db.agentDao().getAll().map { e ->
                    AgentRow(
                        id = e.id,
                        name = e.name,
                        type = e.type,
                        configJson = e.configJson,
                        createdAt = e.createdAt,
                        updatedAt = e.updatedAt,
                    )
                }
                withContext(Dispatchers.Main) { callback(Result.success(rows)) }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) { callback(Result.failure(e)) }
            }
        }
    }

    // ── Message ────────────────────────────────────────────────────────────

    fun insertMessage(row: MessageRow, callback: (Result<Unit>) -> Unit) {
        scope.launch {
            val now = System.currentTimeMillis()
            runCatching {
                db.messageDao().insert(
                    MessageEntity(
                        id = row.id,
                        agentId = row.agentId,
                        role = row.role,
                        content = row.content,
                        status = row.status,
                        createdAt = row.createdAt,
                        updatedAt = row.updatedAt,
                    )
                )
            }.let { withContext(Dispatchers.Main) { callback(it) } }
        }
    }

    fun updateMessageStatus(id: String, status: String, callback: (Result<Unit>) -> Unit) {
        scope.launch {
            runCatching {
                db.messageDao().updateStatus(id, status, System.currentTimeMillis())
            }.let { withContext(Dispatchers.Main) { callback(it) } }
        }
    }

    fun appendMessageContent(id: String, delta: String, callback: (Result<Unit>) -> Unit) {
        scope.launch {
            runCatching {
                db.messageDao().appendContent(id, delta, System.currentTimeMillis())
            }.let { withContext(Dispatchers.Main) { callback(it) } }
        }
    }

    fun getMessages(agentId: String, limit: Long, callback: (Result<List<MessageRow>>) -> Unit) {
        scope.launch {
            try {
                val rows = db.messageDao().getMessages(agentId, limit.toInt()).map { e ->
                    MessageRow(
                        id = e.id,
                        agentId = e.agentId,
                        role = e.role,
                        content = e.content,
                        status = e.status,
                        createdAt = e.createdAt,
                        updatedAt = e.updatedAt,
                    )
                }
                withContext(Dispatchers.Main) { callback(Result.success(rows)) }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) { callback(Result.failure(e)) }
            }
        }
    }

    // ── McpServer ──────────────────────────────────────────────────────────

    fun upsertMcpServer(row: McpServerRow, callback: (Result<Unit>) -> Unit) {
        scope.launch {
            runCatching {
                db.mcpServerDao().upsert(
                    McpServerEntity(
                        id = row.id,
                        agentId = row.agentId,
                        name = row.name,
                        url = row.url,
                        transport = row.transport,
                        authHeader = row.authHeader,
                        enabledToolsJson = row.enabledToolsJson,
                        isEnabled = row.isEnabled,
                        createdAt = row.createdAt,
                    )
                )
            }.let { withContext(Dispatchers.Main) { callback(it) } }
        }
    }

    fun deleteMcpServer(id: String, callback: (Result<Unit>) -> Unit) {
        scope.launch {
            runCatching { db.mcpServerDao().delete(id) }
                .let { withContext(Dispatchers.Main) { callback(it) } }
        }
    }

    fun getMcpServersByAgent(agentId: String, callback: (Result<List<McpServerRow>>) -> Unit) {
        scope.launch {
            try {
                val rows = db.mcpServerDao().getByAgent(agentId).map { e ->
                    McpServerRow(
                        id = e.id,
                        agentId = e.agentId,
                        name = e.name,
                        url = e.url,
                        transport = e.transport,
                        authHeader = e.authHeader,
                        enabledToolsJson = e.enabledToolsJson,
                        isEnabled = e.isEnabled,
                        createdAt = e.createdAt,
                    )
                }
                withContext(Dispatchers.Main) { callback(Result.success(rows)) }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) { callback(Result.failure(e)) }
            }
        }
    }
}

// ── Data classes (mirrors of Pigeon-generated, used before codegen) ────────

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
