package com.aiagent.local_db

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import com.aiagent.local_db.dao.*
import com.aiagent.local_db.entity.*

@Database(
    entities = [
        ServiceConfigEntity::class,
        AgentEntity::class,
        MessageEntity::class,
        MessageEventEntity::class,
        McpServerEntity::class,
    ],
    version = 2,
    exportSchema = false,
)
abstract class AppDatabase : RoomDatabase() {
    abstract fun serviceConfigDao(): ServiceConfigDao
    abstract fun agentDao(): AgentDao
    abstract fun messageDao(): MessageDao
    abstract fun messageEventDao(): MessageEventDao
    abstract fun mcpServerDao(): McpServerDao

    companion object {
        @Volatile
        private var INSTANCE: AppDatabase? = null

        fun getInstance(context: Context): AppDatabase =
            INSTANCE ?: synchronized(this) {
                INSTANCE ?: Room.databaseBuilder(
                    context.applicationContext,
                    AppDatabase::class.java,
                    "ai_agent_client.db",
                )
                    // 内测期不做历史迁移：schema 变更直接重建库
                    .fallbackToDestructiveMigration()
                    .build().also { INSTANCE = it }
            }
    }
}
