package com.aiagent.local_db.entity

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(tableName = "service_configs")
data class ServiceConfigEntity(
    @PrimaryKey val id: String,
    val type: String,      // stt | tts | llm | sts | translation
    val vendor: String,
    val name: String,
    val configJson: String,
    val createdAt: Long,
)

@Entity(tableName = "agents")
data class AgentEntity(
    @PrimaryKey val id: String,
    val name: String,
    val type: String,      // chat | translate
    val configJson: String,
    val createdAt: Long,
    val updatedAt: Long,
)

@Entity(
    tableName = "messages",
    foreignKeys = [
        ForeignKey(
            entity = AgentEntity::class,
            parentColumns = ["id"],
            childColumns = ["agentId"],
            onDelete = ForeignKey.CASCADE,
        )
    ],
    indices = [Index("agentId")],
)
data class MessageEntity(
    @PrimaryKey val id: String,       // requestId (UUID)
    val agentId: String,
    val role: String,                 // user | assistant | system
    val content: String,
    val status: String,               // pending | streaming | done | cancelled | error
    val createdAt: Long,
    val updatedAt: Long,
)

@Entity(
    tableName = "mcp_servers",
    foreignKeys = [
        ForeignKey(
            entity = AgentEntity::class,
            parentColumns = ["id"],
            childColumns = ["agentId"],
            onDelete = ForeignKey.CASCADE,
        )
    ],
    indices = [Index("agentId")],
)
data class McpServerEntity(
    @PrimaryKey val id: String,
    val agentId: String,
    val name: String,
    val url: String,
    val transport: String,            // sse | http
    val authHeader: String?,
    val enabledToolsJson: String,
    val isEnabled: Boolean,
    val createdAt: Long,
)
