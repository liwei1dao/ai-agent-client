package com.aiagent.translate_server

import com.aiagent.device_manager.DefaultNativeDeviceManager
import com.aiagent.device_plugin_interface.DeviceCallTranslationPort
import com.aiagent.device_plugin_interface.DeviceConnectionState

/**
 * 当前 active session 的通话翻译能力端口定位器（vendor-agnostic）。
 *
 * 走 [DefaultNativeDeviceManager.activeSession] → [NativeDeviceSession.callTranslationPort]，
 * 不再硬钉具体厂商。新增设备 vendor 时只需在它的 NativeDeviceSession 实现里
 * override `callTranslationPort()` 即可被本编排器消费。
 */
internal object DevicePortLocator {

    fun activeCallTranslationPort(): DeviceCallTranslationPort? {
        val session = DefaultNativeDeviceManager.get().activeSession ?: return null
        if (session.state != DeviceConnectionState.READY) return null
        return runCatching { session.callTranslationPort() }.getOrNull()
    }
}
