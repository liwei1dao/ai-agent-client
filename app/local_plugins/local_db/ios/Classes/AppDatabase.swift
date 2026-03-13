import Foundation
import GRDB

/// AppDatabase — iOS 数据中心（GRDB）
/// agent_runtime 可直接调用，无需 Channel 开销
final class AppDatabase {
    static let shared = AppDatabase()

    private let dbQueue: DatabaseQueue

    private init() {
        let fileManager = FileManager.default
        let appSupport = try! fileManager
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dbURL = appSupport.appendingPathComponent("ai_agent_client.db")

        dbQueue = try! DatabaseQueue(path: dbURL.path)
        try! migrator.migrate(dbQueue)
    }

    // ─────────────────────────────────────────────────
    // MARK: — Migrations
    // ─────────────────────────────────────────────────

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "service_configs") { t in
                t.column("id", .text).primaryKey()
                t.column("type", .text).notNull()
                t.column("vendor", .text).notNull()
                t.column("name", .text).notNull()
                t.column("configJson", .text).notNull()
                t.column("createdAt", .integer).notNull()
            }
            try db.create(table: "agents") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("type", .text).notNull()
                t.column("configJson", .text).notNull()
                t.column("createdAt", .integer).notNull()
                t.column("updatedAt", .integer).notNull()
            }
            try db.create(table: "messages") { t in
                t.column("id", .text).primaryKey()           // requestId
                t.column("agentId", .text).notNull()
                    .references("agents", onDelete: .cascade)
                t.column("role", .text).notNull()
                t.column("content", .text).notNull()
                t.column("status", .text).notNull()
                t.column("createdAt", .integer).notNull()
                t.column("updatedAt", .integer).notNull()
            }
            try db.create(table: "mcp_servers") { t in
                t.column("id", .text).primaryKey()
                t.column("agentId", .text).notNull()
                    .references("agents", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("url", .text).notNull()
                t.column("transport", .text).notNull()
                t.column("authHeader", .text)
                t.column("enabledToolsJson", .text).notNull()
                t.column("isEnabled", .boolean).notNull()
                t.column("createdAt", .integer).notNull()
            }
        }
        return migrator
    }

    // ─────────────────────────────────────────────────
    // MARK: — ServiceConfig
    // ─────────────────────────────────────────────────

    func upsertServiceConfig(_ row: ServiceConfigRecord) throws {
        try dbQueue.write { db in
            try row.save(db)
        }
    }

    func deleteServiceConfig(id: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM service_configs WHERE id = ?", arguments: [id])
        }
    }

    func getAllServiceConfigs() throws -> [ServiceConfigRecord] {
        try dbQueue.read { db in
            try ServiceConfigRecord.fetchAll(db)
        }
    }

    // ─────────────────────────────────────────────────
    // MARK: — Agent
    // ─────────────────────────────────────────────────

    func upsertAgent(_ row: AgentRecord) throws {
        try dbQueue.write { db in try row.save(db) }
    }

    func deleteAgent(id: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM agents WHERE id = ?", arguments: [id])
        }
    }

    func getAllAgents() throws -> [AgentRecord] {
        try dbQueue.read { db in try AgentRecord.fetchAll(db) }
    }

    // ─────────────────────────────────────────────────
    // MARK: — Message
    // ─────────────────────────────────────────────────

    func insertMessage(_ row: MessageRecord) throws {
        try dbQueue.write { db in try row.insert(db) }
    }

    func updateMessageStatus(id: String, status: String) throws {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE messages SET status = ?, updatedAt = ? WHERE id = ?",
                arguments: [status, now, id]
            )
        }
    }

    func appendMessageContent(id: String, delta: String) throws {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE messages SET content = content || ?, updatedAt = ? WHERE id = ?",
                arguments: [delta, now, id]
            )
        }
    }

    func getMessages(agentId: String, limit: Int) throws -> [MessageRecord] {
        try dbQueue.read { db in
            try MessageRecord.fetchAll(
                db,
                sql: "SELECT * FROM messages WHERE agentId = ? ORDER BY createdAt DESC LIMIT ?",
                arguments: [agentId, limit]
            )
        }
    }

    // ─────────────────────────────────────────────────
    // MARK: — McpServer
    // ─────────────────────────────────────────────────

    func upsertMcpServer(_ row: McpServerRecord) throws {
        try dbQueue.write { db in try row.save(db) }
    }

    func deleteMcpServer(id: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM mcp_servers WHERE id = ?", arguments: [id])
        }
    }

    func getMcpServersByAgent(agentId: String) throws -> [McpServerRecord] {
        try dbQueue.read { db in
            try McpServerRecord.fetchAll(
                db,
                sql: "SELECT * FROM mcp_servers WHERE agentId = ? ORDER BY createdAt ASC",
                arguments: [agentId]
            )
        }
    }
}

// ─────────────────────────────────────────────────
// MARK: — GRDB Record 定义
// ─────────────────────────────────────────────────

struct ServiceConfigRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "service_configs"
    var id: String
    var type: String
    var vendor: String
    var name: String
    var configJson: String
    var createdAt: Int64
}

struct AgentRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "agents"
    var id: String
    var name: String
    var type: String
    var configJson: String
    var createdAt: Int64
    var updatedAt: Int64
}

struct MessageRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "messages"
    var id: String           // requestId
    var agentId: String
    var role: String
    var content: String
    var status: String
    var createdAt: Int64
    var updatedAt: Int64
}

struct McpServerRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "mcp_servers"
    var id: String
    var agentId: String
    var name: String
    var url: String
    var transport: String
    var authHeader: String?
    var enabledToolsJson: String
    var isEnabled: Bool
    var createdAt: Int64
}
