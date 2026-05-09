package com.aiagent.translation_aliyun

import android.util.Log
import com.aiagent.plugin_interface.NativeServiceRegistry
import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * TranslationAliyunPlugin — 阿里云翻译 Flutter 插件
 *
 * 在 onAttachedToEngine 时注册 NativeTranslationService 到 NativeServiceRegistry。
 */
class TranslationAliyunPlugin : FlutterPlugin {

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        NativeServiceRegistry.registerTranslation("aliyun") { TranslationAliyunService() }
        Log.d("TranslationAliyunPlugin", "Registered NativeTranslationService vendor=aliyun")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {}
}
