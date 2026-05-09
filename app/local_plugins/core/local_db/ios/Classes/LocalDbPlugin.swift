import Flutter

public class LocalDbPlugin: NSObject, FlutterPlugin {
    private var channel: FlutterMethodChannel?
    private let db = AppDatabase.shared

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = LocalDbPlugin()
        instance.channel = FlutterMethodChannel(
            name: "local_db/commands",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(instance, channel: instance.channel!)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let value: Any? = try self.dispatch(call.method, args: args)
                DispatchQueue.main.async { result(value) }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "DB_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }

    private func dispatch(_ method: String, args: [String: Any]) throws -> Any? {
        switch method {

        // ── ServiceConfig ────────────────────────────────────────────────
        case "upsertServiceConfig":
            try db.upsertServiceConfig(ServiceConfigRecord(
                id: args["id"] as! String,
                type: args["type"] as! String,
                vendor: args["vendor"] as! String,
                name: args["name"] as! String,
                configJson: args["configJson"] as! String,
                createdAt: Int64(args["createdAt"] as! Int)
            ))
            return nil

        case "deleteServiceConfig":
            try db.deleteServiceConfig(id: args["id"] as! String)
            return nil

        case "getAllServiceConfigs":
            return try db.getAllServiceConfigs().map { e in
                [
                    "id": e.id, "type": e.type, "vendor": e.vendor,
                    "name": e.name, "configJson": e.configJson,
                    "createdAt": e.createdAt,
                ] as [String: Any]
            }

        // ── Agent ────────────────────────────────────────────────────────
        case "upsertAgent":
            try db.upsertAgent(AgentRecord(
                id: args["id"] as! String,
                name: args["name"] as! String,
                type: args["type"] as! String,
                configJson: args["configJson"] as! String,
                createdAt: Int64(args["createdAt"] as! Int),
                updatedAt: Int64(args["updatedAt"] as! Int)
            ))
            return nil

        case "deleteAgent":
            try db.deleteAgent(id: args["id"] as! String)
            return nil

        case "getAllAgents":
            return try db.getAllAgents().map { e in
                [
                    "id": e.id, "name": e.name, "type": e.type,
                    "configJson": e.configJson,
                    "createdAt": e.createdAt, "updatedAt": e.updatedAt,
                ] as [String: Any]
            }

        // ── Message ──────────────────────────────────────────────────────
        case "getMessages":
            let agentId = args["agentId"] as! String
            let limit = args["limit"] as! Int
            return try db.getMessages(agentId: agentId, limit: limit).map { e in
                [
                    "id": e.id, "agentId": e.agentId, "role": e.role,
                    "content": e.content, "status": e.status,
                    "createdAt": e.createdAt, "updatedAt": e.updatedAt,
                ] as [String: Any]
            }

        case "deleteMessages":
            try db.deleteMessagesByAgent(agentId: args["agentId"] as! String)
            return nil

        // ── McpServer ────────────────────────────────────────────────────
        case "upsertMcpServer":
            try db.upsertMcpServer(McpServerRecord(
                id: args["id"] as! String,
                agentId: args["agentId"] as! String,
                name: args["name"] as! String,
                url: args["url"] as! String,
                transport: args["transport"] as! String,
                authHeader: args["authHeader"] as? String,
                enabledToolsJson: args["enabledToolsJson"] as! String,
                isEnabled: args["isEnabled"] as! Bool,
                createdAt: Int64(args["createdAt"] as! Int)
            ))
            return nil

        case "deleteMcpServer":
            try db.deleteMcpServer(id: args["id"] as! String)
            return nil

        case "getMcpServersByAgent":
            let agentId = args["agentId"] as! String
            return try db.getMcpServersByAgent(agentId: agentId).map { e in
                [
                    "id": e.id, "agentId": e.agentId, "name": e.name,
                    "url": e.url, "transport": e.transport,
                    "authHeader": e.authHeader as Any,
                    "enabledToolsJson": e.enabledToolsJson,
                    "isEnabled": e.isEnabled, "createdAt": e.createdAt,
                ] as [String: Any]
            }

        default:
            return FlutterMethodNotImplemented
        }
    }
}
