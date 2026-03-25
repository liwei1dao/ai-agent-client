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
            put("target_lang", targetLang.uppercase())
            if (sourceLang != null) put("source_lang", sourceLang.uppercase())
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
}
