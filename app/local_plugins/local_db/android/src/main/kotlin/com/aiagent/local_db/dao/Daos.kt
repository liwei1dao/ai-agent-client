package com.aiagent.local_db.dao

import androidx.room.*
import com.aiagent.local_db.entity.*

@Dao
interface ServiceConfigDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: ServiceConfigEntity)

    @Query("DELETE FROM service_configs WHERE id = :id")
    suspend fun delete(id: String)

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
interface McpServerDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: McpServerEntity)

    @Query("DELETE FROM mcp_servers WHERE id = :id")
    suspend fun delete(id: String)

    @Query("SELECT * FROM mcp_servers WHERE agentId = :agentId ORDER BY createdAt ASC")
    suspend fun getByAgent(agentId: String): List<McpServerEntity>
}
