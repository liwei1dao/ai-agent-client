package com.aiagent.translation_deepl

import android.util.Log
import com.aiagent.plugin_interface.NativeServiceRegistry
import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * TranslationDeeplPlugin — DeepL 翻译 Flutter 插件
 *
 * 在 onAttachedToEngine 时注册 NativeTranslationService 到 NativeServiceRegistry。
 * Dart 侧纯 HTTP 实现保留向后兼容。
 */
class TranslationDeeplPlugin : FlutterPlugin {

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        NativeServiceRegistry.registerTranslation("deepl") { TranslationDeeplService() }
        Log.d("TranslationDeeplPlugin", "Registered NativeTranslationService vendor=deepl")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {}
}
