import Foundation

/// MCP (Model Context Protocol) service contract.
///
/// One instance corresponds to a single MCP server. Aggregation across
/// multiple servers happens inside the agent's `NativeMcpRouter`.
public protocol NativeMcpService: AnyObject {
    /// Perform the handshake.
    /// `configJson` = serialized McpServerConfig
    /// `{id, name, url, authHeader, enabledTools, timeoutSeconds, extraHeaders}`.
    func initialize(configJson: String) async throws

    /// Tools advertised by the server, filtered by `enabledTools`.
    /// Returns `[{name, description, inputSchema, serverId}, …]`.
    func listTools() async throws -> [[String: Any?]]

    /// Invoke a tool. Returns `{content: String, isError: Bool}`.
    func callTool(toolName: String, argsJson: String) async throws -> [String: Any?]

    func dispose()
}
