import Foundation

/// McpStreamableHttpService — MCP Streamable HTTP transport（MCP 2024-11-05）（iOS 端）
///
/// 协议要点：
///   - 单一 endpoint，所有方法走 POST
///   - 请求 body 为 JSON-RPC 2.0
///   - 响应 Content-Type 可能是 `application/json` 或 `text/event-stream`
///   - 会话头：`Mcp-Session-Id`，server 在 `initialize` 响应中返回，后续请求必须回带
///
/// 本文件目前**未启用**：iOS native 链路尚未铺开（参见 `NativeMcpService.swift`
/// 顶部说明）。当 iOS 端 chat agent 链路整体启动时，把它注册进 iOS 版的
/// `NativeServiceRegistry`（注册键 `streamable_http`）即可对接。
///
/// 单实例对应单 server。多 server 聚合应由 iOS 版 `NativeMcpRouter` 负责。
public final class McpStreamableHttpService: NativeMcpService {

    private static let protocolVersion = "2024-11-05"

    private var session: URLSession?
    private var url: URL?
    private var authHeader: String?
    private var extraHeaders: [String: String] = [:]
    private var enabledTools: Set<String> = []
    private var serverId: String = ""
    private var timeoutSeconds: TimeInterval = 30

    private var sessionId: String?
    private var initialized: Bool = false
    private var rpcId: Int = 0

    public init() {}

    // MARK: - NativeMcpService

    public func initialize(configJson: String) async throws {
        dispose()

        guard let data = configJson.data(using: .utf8),
              let cfg = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw NSError(domain: "mcp.invalid_config", code: -1)
        }

        serverId = cfg["id"] as? String ?? ""
        guard let urlStr = cfg["url"] as? String, !urlStr.isEmpty,
              let parsed = URL(string: urlStr)
        else {
            throw NSError(domain: "mcp.invalid_config", code: -1, userInfo: [NSLocalizedDescriptionKey: "url required"])
        }
        self.url = parsed
        self.authHeader = (cfg["authHeader"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        self.timeoutSeconds = TimeInterval(cfg["timeoutSeconds"] as? Int ?? 30)
        self.enabledTools = Set((cfg["enabledTools"] as? [String]) ?? [])
        if let extras = cfg["extraHeaders"] as? [String: String] {
            self.extraHeaders = extras
        }

        let sessConfig = URLSessionConfiguration.default
        sessConfig.timeoutIntervalForRequest = timeoutSeconds
        sessConfig.timeoutIntervalForResource = timeoutSeconds
        self.session = URLSession(configuration: sessConfig)

        // JSON-RPC initialize 握手
        let initParams: [String: Any] = [
            "protocolVersion": Self.protocolVersion,
            "capabilities": ["tools": [String: Any]()],
            "clientInfo": ["name": "ai-agent-client", "version": "1.0.0"],
        ]
        let initResult = try await rpc("initialize", params: initParams)
        if initResult["protocolVersion"] == nil && initResult["serverInfo"] == nil {
            throw NSError(domain: "mcp.handshake_failed", code: -1, userInfo: [NSLocalizedDescriptionKey: "initialize 响应缺少 protocolVersion / serverInfo"])
        }
        try await rpcNotification("notifications/initialized", params: [String: Any]())
        initialized = true
    }

    public func listTools() async throws -> [[String: Any?]] {
        try ensureReady()
        let result = try await rpc("tools/list", params: [String: Any]())
        guard let arr = result["tools"] as? [[String: Any]] else { return [] }
        var out: [[String: Any?]] = []
        for t in arr {
            guard let name = t["name"] as? String, !name.isEmpty else { continue }
            if !enabledTools.isEmpty && !enabledTools.contains(name) { continue }
            out.append([
                "name": name,
                "description": (t["description"] as? String) ?? "",
                "inputSchema": (t["inputSchema"] as? [String: Any]) ?? [:],
                "serverId": serverId,
            ])
        }
        return out
    }

    public func callTool(toolName: String, argsJson: String) async throws -> [String: Any?] {
        try ensureReady()
        let argsObj: [String: Any]
        if argsJson.isEmpty {
            argsObj = [:]
        } else if let data = argsJson.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            argsObj = parsed
        } else {
            argsObj = [:]
        }
        let result = try await rpc("tools/call", params: ["name": toolName, "arguments": argsObj])
        let isError = (result["isError"] as? Bool) ?? false
        var text = ""
        if let arr = result["content"] as? [[String: Any]] {
            for c in arr where (c["type"] as? String) == "text" {
                if let t = c["text"] as? String, !t.isEmpty {
                    if !text.isEmpty { text += "\n" }
                    text += t
                }
            }
        }
        return ["content": text, "isError": isError]
    }

    public func dispose() {
        session?.invalidateAndCancel()
        session = nil
        url = nil
        authHeader = nil
        extraHeaders.removeAll()
        enabledTools.removeAll()
        sessionId = nil
        initialized = false
        rpcId = 0
    }

    // MARK: - Internal

    private func ensureReady() throws {
        guard session != nil else {
            throw NSError(domain: "mcp.disposed", code: -1)
        }
        guard initialized else {
            throw NSError(domain: "mcp.not_initialized", code: -1, userInfo: [NSLocalizedDescriptionKey: "call initialize() first"])
        }
    }

    private func buildRequest(body: Data) throws -> URLRequest {
        guard let url = url else { throw NSError(domain: "mcp.disposed", code: -1) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if let auth = authHeader { req.setValue(auth, forHTTPHeaderField: "Authorization") }
        if let sid = sessionId { req.setValue(sid, forHTTPHeaderField: "Mcp-Session-Id") }
        for (k, v) in extraHeaders { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = body
        return req
    }

    private func rpc(_ method: String, params: [String: Any]) async throws -> [String: Any] {
        rpcId += 1
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": rpcId,
            "method": method,
            "params": params,
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        let req = try buildRequest(body: data)
        guard let session = session else { throw NSError(domain: "mcp.disposed", code: -1) }
        let (respData, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "mcp.invalid_response", code: -1)
        }
        if let sid = http.value(forHTTPHeaderField: "Mcp-Session-Id"), !sid.isEmpty {
            sessionId = sid
        }
        if http.statusCode != 200 && http.statusCode != 202 {
            let snippet = String(data: respData, encoding: .utf8)?.prefix(200) ?? ""
            throw NSError(domain: "mcp.http_\(http.statusCode)", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: String(snippet)])
        }
        let rpcObj = try parseRpcBody(data: respData, contentType: http.value(forHTTPHeaderField: "Content-Type") ?? "")
        if let err = rpcObj["error"] as? [String: Any] {
            let code = err["code"] as? Int ?? -1
            let msg = err["message"] as? String ?? ""
            throw NSError(domain: "mcp.rpc_\(code)", code: code, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return (rpcObj["result"] as? [String: Any]) ?? [:]
    }

    private func rpcNotification(_ method: String, params: [String: Any]) async throws {
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        let req = try buildRequest(body: data)
        guard let session = session else { throw NSError(domain: "mcp.disposed", code: -1) }
        let (_, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse,
           let sid = http.value(forHTTPHeaderField: "Mcp-Session-Id"), !sid.isEmpty {
            sessionId = sid
        }
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw NSError(domain: "mcp.http_\(http.statusCode)", code: http.statusCode)
        }
    }

    private func parseRpcBody(data: Data, contentType: String) throws -> [String: Any] {
        if contentType.lowercased().contains("text/event-stream") {
            let body = String(data: data, encoding: .utf8) ?? ""
            for raw in body.split(separator: "\n") {
                let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.hasPrefix("data:") {
                    let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                    if payload.isEmpty { continue }
                    if let pdata = payload.data(using: .utf8),
                       let obj = try JSONSerialization.jsonObject(with: pdata) as? [String: Any] {
                        return obj
                    }
                }
            }
            throw NSError(domain: "mcp.invalid_response", code: -1, userInfo: [NSLocalizedDescriptionKey: "SSE 响应未包含 JSON-RPC data 帧"])
        }
        if data.isEmpty { return [:] }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "mcp.invalid_response", code: -1)
        }
        return obj
    }
}
