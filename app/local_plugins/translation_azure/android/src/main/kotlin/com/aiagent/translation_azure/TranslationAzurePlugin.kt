package com.aiagent.translation_azure

import android.util.Log
import com.aiagent.plugin_interface.NativeServiceRegistry
import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * TranslationAzurePlugin — Microsoft / Azure Translator Flutter 插件
 *
 * 在 onAttachedToEngine 时把 NativeTranslationService 注册到 NativeServiceRegistry。
 */
class TranslationAzurePlugin : FlutterPlugin {

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        NativeServiceRegistry.registerTranslation("azure") { TranslationAzureService() }
        Log.d("TranslationAzure", "Registered NativeTranslationService vendor=azure")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {}
}
