package com.aiagent.plugin_interface

import android.util.Log

/**
 * NativeServiceRegistry — 服务插件注册表（全局单例）
 *
 * 每个服务插件在 FlutterPlugin.onAttachedToEngine() 时注册自己的工厂方法。
 * Agent 类型插件通过 vendor 名称获取对应服务实例。
 *
 * 使用示例：
 *   // 注册（stt_azure 插件的 onAttachedToEngine 中）
 *   NativeServiceRegistry.registerStt("azure") { SttAzureService(context) }
 *
 *   // 获取（agent_chat 的 initialize 中）
 *   val sttService = NativeServiceRegistry.createStt("azure")
 */
object NativeServiceRegistry {

    private const val TAG = "NativeServiceRegistry"

    private val sttFactories = mutableMapOf<String, () -> NativeSttService>()
    private val ttsFactories = mutableMapOf<String, () -> NativeTtsService>()
    private val llmFactories = mutableMapOf<String, () -> NativeLlmService>()
    private val stsFactories = mutableMapOf<String, () -> NativeStsService>()
    private val astFactories = mutableMapOf<String, () -> NativeAstService>()
    private val translationFactories = mutableMapOf<String, () -> NativeTranslationService>()

    // ── 注册 ─────────────────────────────────────────

    fun registerStt(vendor: String, factory: () -> NativeSttService) {
        sttFactories[vendor] = factory
        Log.d(TAG, "Registered STT vendor: $vendor")
    }

    fun registerTts(vendor: String, factory: () -> NativeTtsService) {
        ttsFactories[vendor] = factory
        Log.d(TAG, "Registered TTS vendor: $vendor")
    }

    fun registerLlm(vendor: String, factory: () -> NativeLlmService) {
        llmFactories[vendor] = factory
        Log.d(TAG, "Registered LLM vendor: $vendor")
    }

    fun registerSts(vendor: String, factory: () -> NativeStsService) {
        stsFactories[vendor] = factory
        Log.d(TAG, "Registered STS vendor: $vendor")
    }

    fun registerAst(vendor: String, factory: () -> NativeAstService) {
        astFactories[vendor] = factory
        Log.d(TAG, "Registered AST vendor: $vendor")
    }

    fun registerTranslation(vendor: String, factory: () -> NativeTranslationService) {
        translationFactories[vendor] = factory
        Log.d(TAG, "Registered Translation vendor: $vendor")
    }

    // ── 创建 ─────────────────────────────────────────

    fun createStt(vendor: String): NativeSttService =
        sttFactories[vendor]?.invoke()
            ?: throw IllegalArgumentException("No STT service registered for vendor: $vendor. Available: ${sttFactories.keys}")

    fun createTts(vendor: String): NativeTtsService =
        ttsFactories[vendor]?.invoke()
            ?: throw IllegalArgumentException("No TTS service registered for vendor: $vendor. Available: ${ttsFactories.keys}")

    fun createLlm(vendor: String): NativeLlmService =
        llmFactories[vendor]?.invoke()
            ?: throw IllegalArgumentException("No LLM service registered for vendor: $vendor. Available: ${llmFactories.keys}")

    fun createSts(vendor: String): NativeStsService =
        stsFactories[vendor]?.invoke()
            ?: throw IllegalArgumentException("No STS service registered for vendor: $vendor. Available: ${stsFactories.keys}")

    fun createAst(vendor: String): NativeAstService =
        astFactories[vendor]?.invoke()
            ?: throw IllegalArgumentException("No AST service registered for vendor: $vendor. Available: ${astFactories.keys}")

    fun createTranslation(vendor: String): NativeTranslationService =
        translationFactories[vendor]?.invoke()
            ?: throw IllegalArgumentException("No Translation service registered for vendor: $vendor. Available: ${translationFactories.keys}")

    // ── 查询 ─────────────────────────────────────────

    fun availableSttVendors(): Set<String> = sttFactories.keys
    fun availableTtsVendors(): Set<String> = ttsFactories.keys
    fun availableLlmVendors(): Set<String> = llmFactories.keys
    fun availableStsVendors(): Set<String> = stsFactories.keys
    fun availableAstVendors(): Set<String> = astFactories.keys
    fun availableTranslationVendors(): Set<String> = translationFactories.keys
}
