package com.aiagent.plugin_interface

/**
 * 翻译服务原生接口
 *
 * 实现方：translation_deepl, translation_aliyun 等服务插件
 * 使用方：agent_translate
 *
 * 职责：文本翻译（HTTP API 调用）
 */
interface NativeTranslationService {

    /**
     * 初始化翻译服务
     * @param configJson  服务配置 JSON（apiKey 等）
     */
    fun initialize(configJson: String)

    /**
     * 翻译文本
     *
     * @param text          要翻译的文本
     * @param targetLang    目标语言代码（如 "en", "zh"）
     * @param sourceLang    源语言代码（可选，null 表示自动检测）
     * @return 翻译结果
     */
    suspend fun translate(
        text: String,
        targetLang: String,
        sourceLang: String? = null,
    ): NativeTranslationResult

    /** 释放资源 */
    fun release()
}
