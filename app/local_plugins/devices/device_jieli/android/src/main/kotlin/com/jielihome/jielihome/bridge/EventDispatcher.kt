package com.jielihome.jielihome.bridge

import android.os.Handler
import android.os.Looper
import com.jielihome.jielihome.api.JieliEventListener
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.CopyOnWriteArrayList

/**
 * 事件总线。所有 forwarder / feature 调用 [send]，由本类做 fan-out：
 *   - Flutter 端：通过 EventChannel.EventSink 推到 Dart
 *   - 原生端：通过 [JieliEventListener] 推给宿主直接订阅
 *
 * Flutter / 原生 / 多个原生监听器 可以同时存在；payload 形态完全一致。
 */
class EventDispatcher : EventChannel.StreamHandler {

    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var sink: EventChannel.EventSink? = null

    private val nativeListeners = CopyOnWriteArrayList<JieliEventListener>()

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    fun addNativeListener(listener: JieliEventListener) {
        if (!nativeListeners.contains(listener)) nativeListeners.add(listener)
    }

    fun removeNativeListener(listener: JieliEventListener) {
        nativeListeners.remove(listener)
    }

    fun send(payload: Map<String, Any?>) {
        // 原生监听同步派发（在事件原始线程，不经主线程切换，方便高频音频帧）
        for (l in nativeListeners) {
            try { l.onEvent(payload) } catch (_: Throwable) { /* swallow listener errors */ }
        }
        // Flutter 端必须在主线程
        val s = sink ?: return
        mainHandler.post { runCatching { s.success(payload) } }
    }
}
