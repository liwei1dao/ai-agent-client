package com.aiagent.assistant_server

import com.aiagent.device_manager.DefaultNativeDeviceManager
import com.aiagent.device_plugin_interface.DeviceAssistantPort
import com.aiagent.device_plugin_interface.DeviceConnectionState

/**
 * 当前 active session 的 AI 助理能力端口定位器（vendor-agnostic）。
 *
 * 走 [DefaultNativeDeviceManager.activeSession] → [NativeDeviceSession.assistantPort]，
 * 不再依赖 [com.aiagent.device_plugin_interface.DeviceCallTranslationPort]（翻译语义）。
 * 新增设备 vendor 时只需在它的 NativeDeviceSession 实现里 override
 * `assistantPort()` 即可被本编排器消费。
 */
internal object DevicePortLocator {

    fun activeAssistantPort(): DeviceAssistantPort? {
        val session = DefaultNativeDeviceManager.get().activeSession ?: return null
        if (session.state != DeviceConnectionState.READY) return null
        return runCatching { session.assistantPort() }.getOrNull()
    }
}
