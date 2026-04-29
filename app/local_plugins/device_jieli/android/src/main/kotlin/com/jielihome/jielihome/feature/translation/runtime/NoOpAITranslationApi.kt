package com.jielihome.jielihome.feature.translation.runtime

import com.jieli.bluetooth.bean.translation.AudioData
import com.jieli.bluetooth.bean.translation.TranslationMode
import com.jieli.bluetooth.interfaces.rcsp.translation.AITranslationCallback
import com.jieli.bluetooth.interfaces.rcsp.translation.IAITranslationApi

/**
 * SDK 的 [TranslationImpl] 构造函数要求一个 [IAITranslationApi]。
 * 我们走的是「外部翻译服务」路线，SDK 自带的 AI 流程不启用，所以这里给个空实现。
 */
internal class NoOpAITranslationApi : IAITranslationApi {
    override fun isWorking(): Boolean = false
    override fun startTranslating(mode: TranslationMode, cb: AITranslationCallback) { /* no-op */ }
    override fun stopTranslating() { /* no-op */ }
    override fun writeAudio(data: AudioData) { /* no-op */ }
}
