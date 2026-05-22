package com.aiagent.translation_volcengine

import android.util.Log
import com.aiagent.plugin_interface.NativeServiceRegistry
import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * TranslationVolcenginePlugin — 火山引擎翻译 Flutter 插件
 *
 * 在 onAttachedToEngine 时注册 NativeTranslationService 到 NativeServiceRegistry。
 */
class TranslationVolcenginePlugin : FlutterPlugin {

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        NativeServiceRegistry.registerTranslation("volcengine") { TranslationVolcengineService() }
        Log.d("TranslationVolcengine", "Registered NativeTranslationService vendor=volcengine")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {}
}
