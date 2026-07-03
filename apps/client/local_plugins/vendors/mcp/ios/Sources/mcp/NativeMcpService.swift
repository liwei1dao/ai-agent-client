import Foundation

/// MCP（Model Context Protocol）服务原生接口（iOS 端）
///
/// 与 Kotlin `NativeMcpService` 对齐。单实例对应单 server。
///
/// 本文件目前**未启用**：iOS native 链路（agent_chat/ios、llm_openai/ios、
/// ai_plugin_interface/ios）尚未铺开，因此该协议没有对应的 podspec/registry
/// 集成。等 iOS native 链路整体启动时把它接进 ai_plugin_interface 的 iOS 模块。
///
/// 生命周期：`uninitialized → initialize(_:) → ready → callTool/listTools → dispose → disposed`
public protocol NativeMcpService: AnyObject {

    /// 握手并就绪
    /// - Parameter configJson: 序列化后的 McpServerConfig
    /// - Throws: 握手失败时抛出，调用方据此把该 server 标记为不可用
    func initialize(configJson: String) async throws

    /// 拉取该 server 的工具列表（按 enabledTools 白名单过滤）
    /// - Returns: `[{"name","description","inputSchema":[String:Any?],"serverId"}]`
    func listTools() async throws -> [[String: Any?]]

    /// 调用工具
    /// - Parameters:
    ///   - toolName: 工具名
    ///   - argsJson: JSON 字符串形式的参数对象
    /// - Returns: `{"content":String, "isError":Bool}`
    func callTool(toolName: String, argsJson: String) async throws -> [String: Any?]

    /// 释放资源
    func dispose()
}
