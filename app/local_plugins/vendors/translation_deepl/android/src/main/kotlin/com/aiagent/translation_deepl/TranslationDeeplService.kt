package com.aiagent.translation_deepl

import android.util.Log
import com.aiagent.plugin_interface.NativeTranslationResult
import com.aiagent.plugin_interface.NativeTranslationService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject

/**
 * TranslationDeeplService — DeepL API v2 翻译原生实现
 */
class TranslationDeeplService : NativeTranslationService {

    companion object {
        private const val TAG = "TranslationDeeplService"
        private const val BASE_URL = "https://api-free.deepl.com/v2"
    }

    private val client = OkHttpClient()
    private var apiKey: String = ""

    override fun initialize(configJson: String) {
        val cfg = JSONObject(configJson)
        apiKey = cfg.optString("apiKey", "")
        Log.d(TAG, "initialize: apiKey=${apiKey.take(8)}...")
    }

    override suspend fun translate(
        text: String,
        targetLang: String,
        sourceLang: String?,
    ): NativeTranslationResult = withContext(Dispatchers.IO) {
        val body = JSONObject().apply {
            put("text", JSONArray().put(text))
            put("target_lang", toDeeplTarget(targetLang))
            val src = sourceLang?.let { toDeeplSource(it) }
            if (!src.isNullOrEmpty()) put("source_lang", src)
        }

        val request = Request.Builder()
            .url("$BASE_URL/translate")
            .post(body.toString().toRequestBody("application/json".toMediaType()))
            .header("Authorization", "DeepL-Auth-Key $apiKey")
            .header("Content-Type", "application/json")
            .build()

        val response = client.newCall(request).execute()
        if (!response.isSuccessful) {
            throw Exception("DeepL API error: ${response.code} ${response.body?.string()?.take(200)}")
        }

        val json = JSONObject(response.body?.string() ?: "{}")
        val translations = json.getJSONArray("translations")
        val first = translations.getJSONObject(0)

        NativeTranslationResult(
            sourceText = text,
            translatedText = first.getString("text"),
            sourceLanguage = first.optString("detected_source_language", sourceLang ?: "auto").lowercase(),
            targetLanguage = targetLang,
        )
    }

    override fun release() {}

    /**
     * canonical（zh-CN / en-US / pt-BR …） → DeepL `target_lang`。
     */
    private fun toDeeplTarget(code: String): String {
        val upper = code.trim().uppercase()
        return when (upper) {
            "ZH", "ZH-CN", "ZH-HANS" -> "ZH-HANS"
            "ZH-TW", "ZH-HK", "ZH-HANT" -> "ZH-HANT"
            "EN", "EN-US" -> "EN-US"
            "EN-GB" -> "EN-GB"
            "PT", "PT-BR" -> "PT-BR"
            "PT-PT" -> "PT-PT"
            else -> upper.substringBefore("-")
        }
    }

    /** canonical → DeepL `source_lang`：基本上是大写两字。auto 时返回空串。*/
    private fun toDeeplSource(code: String): String {
        val upper = code.trim().uppercase()
        if (upper == "AUTO" || upper.isEmpty()) return ""
        return upper.substringBefore("-")
    }
}
