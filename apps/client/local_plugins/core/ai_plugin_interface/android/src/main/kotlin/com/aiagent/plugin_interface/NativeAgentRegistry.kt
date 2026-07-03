package com.aiagent.plugin_interface

import android.util.Log

/**
 * NativeAgentRegistry — Agent 类型插件注册表（全局单例）
 *
 * 每个 Agent 类型插件在 FlutterPlugin.onAttachedToEngine() 时注册自己的工厂方法。
 * agents_server 通过 agentType 名称创建对应的 NativeAgent 实例。
 *
 * 使用示例：
 *   // 注册（agent_chat 插件的 onAttachedToEngine 中）
 *   NativeAgentRegistry.register("chat") { ChatAgentSession() }
 *
 *   // 创建（agents_server 收到 createAgent 命令时）
 *   val agent = NativeAgentRegistry.create("chat")
 *   agent.initialize(config, eventSink, context)
 */
object NativeAgentRegistry {

    private const val TAG = "NativeAgentRegistry"

    private val factories = mutableMapOf<String, () -> NativeAgent>()

    /**
     * 注册 Agent 类型工厂
     * @param agentType  类型标识（"chat", "sts", "translate", "ast"）
     * @param factory    创建 NativeAgent 实例的工厂方法
     */
    fun register(agentType: String, factory: () -> NativeAgent) {
        factories[agentType] = factory
        Log.d(TAG, "Registered agent type: $agentType")
    }

    /**
     * 创建指定类型的 NativeAgent 实例
     * @param agentType  类型标识
     * @return 新的 NativeAgent 实例（未初始化，需调用 initialize）
     */
    fun create(agentType: String): NativeAgent =
        factories[agentType]?.invoke()
            ?: throw IllegalArgumentException(
                "No agent registered for type: $agentType. Available: ${factories.keys}"
            )

    /** 查询所有已注册的 Agent 类型 */
    fun supportedTypes(): Set<String> = factories.keys
}
