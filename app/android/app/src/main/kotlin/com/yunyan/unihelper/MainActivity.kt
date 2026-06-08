package com.yunyan.unihelper

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        /** flutter_overlay_window 的 OverlayConstants.CACHED_TAG */
        private const val OVERLAY_ENGINE_TAG = "myCachedEngine"
        /** 悬浮窗 isolate → 原生：拉起 app */
        private const val OVERLAY_NATIVE_CHANNEL = "desktop_assistant/overlay_native"
        /** 主 isolate ← 原生：消费待导航路由 */
        private const val NAV_CHANNEL = "desktop_assistant/nav"
        private const val EXTRA_ROUTE = "route"
        private const val ASSISTANT_ROUTE = "/ai-assistant"
    }

    /** 悬浮窗点击 / 启动 intent 写入的待导航路由；Flutter 端拉取后清空。 */
    private var pendingRoute: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, NativeLogBridge.CHANNEL)
            .setStreamHandler(NativeLogBridge())

        // 主 engine：Flutter 端启动/resume 时拉取一次待导航路由。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NAV_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "consumePendingRoute" -> {
                        val r = pendingRoute
                        pendingRoute = null
                        result.success(r)
                    }
                    else -> result.notImplemented()
                }
            }

        // overlay engine：悬浮窗点击 → 拉起 app。用 applicationContext，
        // 这样即便本 MainActivity 已销毁 / app 被划掉（进程由 OverlayService 前台
        // 服务保活），handler 仍有效，能重新拉起 app。
        val appCtx = applicationContext
        val overlayEngine = FlutterEngineCache.getInstance().get(OVERLAY_ENGINE_TAG)
        if (overlayEngine != null) {
            MethodChannel(overlayEngine.dartExecutor.binaryMessenger, OVERLAY_NATIVE_CHANNEL)
                .setMethodCallHandler { call, result ->
                    when (call.method) {
                        "launchApp" -> {
                            val launch = appCtx.packageManager
                                .getLaunchIntentForPackage(appCtx.packageName)
                                ?.apply {
                                    addFlags(
                                        Intent.FLAG_ACTIVITY_NEW_TASK or
                                            Intent.FLAG_ACTIVITY_SINGLE_TOP,
                                    )
                                    putExtra(EXTRA_ROUTE, ASSISTANT_ROUTE)
                                }
                            if (launch != null) appCtx.startActivity(launch)
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                }
        }

        // 冷启动 intent 里若带 route，记下待 Flutter 消费。
        consumeRouteFromIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        consumeRouteFromIntent(intent)
    }

    private fun consumeRouteFromIntent(intent: Intent?) {
        intent?.getStringExtra(EXTRA_ROUTE)?.let { pendingRoute = it }
    }
}
