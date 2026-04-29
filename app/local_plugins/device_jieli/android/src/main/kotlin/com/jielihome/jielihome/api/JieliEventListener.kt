package com.jielihome.jielihome.api

/**
 * 原生层事件监听器。宿主 App 在 Activity/Service 里实现并注册到
 * [com.jielihome.jielihome.core.JieliHomeServer.addEventListener]，
 * 即可订阅插件所有事件而不依赖 Flutter EventChannel。
 *
 * 所有回调里的 payload 都是 [Map]，字段与 Dart 侧 EventChannel 推上去的完全一致，
 * 因此原生订阅与 Dart 订阅可以并存（fan-out）。
 *
 * 默认提供「按 type 路由」的便捷扩展，子类只覆盖关心的方法即可。
 */
interface JieliEventListener {
    /** 任意事件，原始 payload。可以自己按 payload["type"] 路由。 */
    fun onEvent(payload: Map<String, Any?>) {}
}

/**
 * 按事件类型分发的便捷适配器。子类只覆盖关心的回调，未覆盖的事件会落到 [onUnknown]。
 */
abstract class JieliEventAdapter : JieliEventListener {

    override fun onEvent(payload: Map<String, Any?>) {
        when (payload["type"] as? String) {
            "adapterStatus" -> onAdapterStatus(
                enabled = payload["enabled"] as? Boolean ?: false,
                hasBle = payload["hasBle"] as? Boolean ?: false,
            )

            "scanStatus" -> onScanStatus(
                ble = payload["ble"] as? Boolean ?: false,
                started = payload["started"] as? Boolean ?: false,
            )

            "deviceFound" -> onDeviceFound(payload)
            "bondStatus" -> onBondStatus(
                address = payload["address"] as? String ?: "",
                status = payload["status"] as? Int ?: 0,
            )
            "rcspInit" -> onRcspInit(
                address = payload["address"] as? String ?: "",
                code = payload["code"] as? Int ?: -1,
            )
            "connectionState" -> onConnectionState(
                address = payload["address"] as? String ?: "",
                state = payload["state"] as? Int ?: -1,
            )

            "battery" -> onBattery(
                address = payload["address"] as? String,
                level = payload["level"] as? Int,
            )
            "phoneCallStatus" -> onPhoneCallStatus(
                address = payload["address"] as? String,
                status = payload["status"] as? Int ?: 0,
            )
            "voiceMode" -> onVoiceMode(
                address = payload["address"] as? String,
                modeId = payload["modeId"] as? Int,
            )

            "volume" -> onVolume(payload)
            "musicName" -> onMusicName(
                address = payload["address"] as? String,
                name = payload["name"] as? String,
            )
            "musicStatus" -> onMusicStatus(payload)
            "playMode" -> onPlayMode(
                address = payload["address"] as? String,
                mode = payload["mode"] as? Int,
            )

            "expandFunction" -> onExpandFunction(payload)

            "translationAudio" -> {
                onTranslationAudio(payload)
                onTranslationEvent(payload)
            }
            "translationResult" -> {
                onTranslationResult(payload)
                onTranslationEvent(payload)
            }
            "translationError" -> {
                onTranslationError(payload)
                onTranslationEvent(payload)
            }
            "translationLog" -> {
                onTranslationLog(payload)
                onTranslationEvent(payload)
            }

            "speechStart" -> onSpeechStart(payload)
            "speechAudio" -> onSpeechAudio(payload)
            "speechEnd" -> onSpeechEnd(payload)
            "speechError" -> onSpeechError(payload)

            "otaState" -> onOtaState(payload)
            "otaError" -> onOtaError(payload)

            else -> onUnknown(payload)
        }
    }

    open fun onAdapterStatus(enabled: Boolean, hasBle: Boolean) {}
    open fun onScanStatus(ble: Boolean, started: Boolean) {}
    open fun onDeviceFound(payload: Map<String, Any?>) {}
    open fun onBondStatus(address: String, status: Int) {}
    open fun onRcspInit(address: String, code: Int) {}
    open fun onConnectionState(address: String, state: Int) {}

    open fun onBattery(address: String?, level: Int?) {}
    open fun onPhoneCallStatus(address: String?, status: Int) {}
    open fun onVoiceMode(address: String?, modeId: Int?) {}

    open fun onVolume(payload: Map<String, Any?>) {}
    open fun onMusicName(address: String?, name: String?) {}
    open fun onMusicStatus(payload: Map<String, Any?>) {}
    open fun onPlayMode(address: String?, mode: Int?) {}

    open fun onExpandFunction(payload: Map<String, Any?>) {}

    /** 翻译事件统一入口（兜底，默认细分回调之后还会触发一次） */
    open fun onTranslationEvent(payload: Map<String, Any?>) {}

    /** payload["pcm"] 为 ByteArray；附带 streamId/sampleRate/seq/tsMs/final 字段 */
    open fun onTranslationAudio(payload: Map<String, Any?>) {}

    /** payload 含 srcLang/srcText/destLang/destText/requestId */
    open fun onTranslationResult(payload: Map<String, Any?>) {}

    /** payload 含 code/message */
    open fun onTranslationError(payload: Map<String, Any?>) {}

    open fun onTranslationLog(payload: Map<String, Any?>) {}

    /** 耳机检测到唤醒/语音助手触发；payload: voiceType, sampleRate, vadWay, address, tsMs */
    open fun onSpeechStart(payload: Map<String, Any?>) {}

    /** 语音助手音频帧；payload: pcm(ByteArray), encoding, sampleRate, channels, address */
    open fun onSpeechAudio(payload: Map<String, Any?>) {}

    /** 语音助手会话结束；payload: reason, message, address */
    open fun onSpeechEnd(payload: Map<String, Any?>) {}

    open fun onSpeechError(payload: Map<String, Any?>) {}

    /** OTA 进度/状态：state(String), sent(Long), total(Long), percent(Int) */
    open fun onOtaState(payload: Map<String, Any?>) {}

    open fun onOtaError(payload: Map<String, Any?>) {}

    open fun onUnknown(payload: Map<String, Any?>) {}
}
