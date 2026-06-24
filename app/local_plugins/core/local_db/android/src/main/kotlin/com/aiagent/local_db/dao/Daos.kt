package com.aiagent.local_db.dao

import androidx.room.*
import com.aiagent.local_db.entity.*

@Dao
interface ServiceConfigDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: ServiceConfigEntity)

    @Query("DELETE FROM service_configs WHERE id = :id")
    suspend fun delete(id: String)

    @Query("SELECT * FROM service_configs WHERE id = :id LIMIT 1")
    suspend fun getById(id: String): ServiceConfigEntity?

    @Query("SELECT * FROM service_configs ORDER BY createdAt DESC")
    suspend fun getAll(): List<ServiceConfigEntity>
}

@Dao
interface AgentDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: AgentEntity)

    @Query("DELETE FROM agents WHERE id = :id")
    suspend fun delete(id: String)

    @Query("SELECT * FROM agents ORDER BY createdAt DESC")
    suspend fun getAll(): List<AgentEntity>
}

@Dao
interface MessageDao {
    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insert(entity: MessageEntity)

    @Query("UPDATE messages SET status = :status, updatedAt = :updatedAt WHERE id = :id")
    suspend fun updateStatus(id: String, status: String, updatedAt: Long)

    @Query("UPDATE messages SET content = content || :delta, updatedAt = :updatedAt WHERE id = :id")
    suspend fun appendContent(id: String, delta: String, updatedAt: Long)

    @Query(
        """SELECT * FROM messages WHERE agentId = :agentId
           ORDER BY createdAt DESC LIMIT :limit"""
    )
    suspend fun getMessages(agentId: String, limit: Int): List<MessageEntity>

    @Query("DELETE FROM messages WHERE agentId = :agentId")
    suspend fun deleteByAgent(agentId: String)
}

@Dao
interface MessageEventDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entity: MessageEventEntity)

    /// 流式累加 inputJson（工具参数 delta / thinking delta）
    @Query("UPDATE message_events SET inputJson = inputJson || :delta WHERE id = :id")
    suspend fun appendInput(id: String, delta: String)

    /// 收尾：写入结果 + 终态
    @Query(
        """UPDATE message_events SET outputJson = :outputJson, status = :status,
           completedAt = :completedAt WHERE id = :id"""
    )
    suspend fun complete(id: String, outputJson: String?, status: String, completedAt: Long)

    /// 取某 agent 最近 limit 条事件（按消息时间倒序），上层按 messageId 分组、seq 升序挂回
    @Query(
        """SELECT * FROM message_events WHERE agentId = :agentId
           ORDER BY createdAt DESC LIMIT :limit"""
    )
    suspend fun getByAgent(agentId: String, limit: Int): List<MessageEventEntity>

    @Query("SELECT * FROM message_events WHERE messageId = :messageId ORDER BY seq ASC")
    suspend fun getByMessage(messageId: String): List<MessageEventEntity>
}

@Dao
interface McpServerDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: McpServerEntity)

    @Query("DELETE FROM mcp_servers WHERE id = :id")
    suspend fun delete(id: String)

    @Query("SELECT * FROM mcp_servers WHERE agentId = :agentId ORDER BY createdAt ASC")
    suspend fun getByAgent(agentId: String): List<McpServerEntity>
}
