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
        McpServerEntity::class,
    ],
    version = 1,
    exportSchema = false,
)
abstract class AppDatabase : RoomDatabase() {
    abstract fun serviceConfigDao(): ServiceConfigDao
    abstract fun agentDao(): AgentDao
    abstract fun messageDao(): MessageDao
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
                ).build().also { INSTANCE = it }
            }
    }
}
