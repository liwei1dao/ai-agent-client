package com.jielihome.jielihome.feature.translation.runtime

import com.jieli.bluetooth.bean.translation.AudioData
import com.jieli.bluetooth.bean.translation.TranslationMode
import com.jieli.bluetooth.interfaces.rcsp.translation.AITranslationCallback
import com.jieli.bluetooth.interfaces.rcsp.translation.IAITranslationApi

/**
 * SDK 的 `TranslationImpl` 构造函数要求一个 [IAITranslationApi]。本类是给**纯录音通路**
 * 占位用的空实现：上层只想拿原始 OPUS / PCM 流（自己挂 `TranslationCallback.onReceiveAudioData`），
 * 不希望 SDK 触发任何 AI 翻译流程 / TTS 注入。
 *
 * # 谁在用
 * - [com.jielihome.jielihome.feature.assistant.JieliAssistantPort]（AI 助理上行通路）
 * - [com.jielihome.jielihome.feature.record.JieliDeviceRecordPort]（通话录音 MODE_CALL_RECORD）
 * - [com.jielihome.jielihome.feature.translation.mode.RecordModeHandler]（MODE_RECORD）
 * - [com.jielihome.jielihome.feature.translation.mode.RecordingTranslationModeHandler]（MODE_RECORDING_TRANSLATION）
 * - [com.jielihome.jielihome.feature.translation.TranslationFeature]（兜底 TranslationImpl 实例）
 *
 * # 谁**不在**用了
 * Call translation（mode 3 / 6）由 [JieliAITranslationBridge] 接管——那条路要的是
 * "SDK 接管 TTS 切包注入"，必须给真正的 IAITranslationApi 实现，避免自己写 writeAudioData
 * 队列触发的"耳机端解码器频繁 reset → 杂音 / 断续"。
 */
internal class NoOpAITranslationApi : IAITranslationApi {
    override fun isWorking(): Boolean = false
    override fun startTranslating(mode: TranslationMode, cb: AITranslationCallback) { /* no-op */ }
    override fun stopTranslating() { /* no-op */ }
    override fun writeAudio(data: AudioData) { /* no-op */ }
}
