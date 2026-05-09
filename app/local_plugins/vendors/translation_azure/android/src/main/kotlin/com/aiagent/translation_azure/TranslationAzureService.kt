package com.aiagent.translation_azure

import android.util.Log
import com.aiagent.plugin_interface.NativeTranslationResult
import com.aiagent.plugin_interface.NativeTranslationService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject

/**
 * TranslationAzureService — Microsoft / Azure Translator v3.0 原生实现
 *
 * 配置：apiKey + region。
 *  - 端点：https://api.cognitive.microsofttranslator.com/translate
 *  - 鉴权：Header `Ocp-Apim-Subscription-Key` + `Ocp-Apim-Subscription-Region`
 */
class TranslationAzureService : NativeTranslationService {

    companion object {
        private const val TAG = "TranslationAzure"
        private const val BASE_URL = "https://api.cognitive.microsofttranslator.com"
    }

    private val client = OkHttpClient()
    private var apiKey: String = ""
    private var region: String = "global"

    override fun initialize(configJson: String) {
        val cfg = JSONObject(configJson)
        apiKey = cfg.optString("apiKey", "")
        val r = cfg.optString("region", "")
        if (r.isNotBlank()) region = r
        Log.d(TAG, "initialize: region=$region apiKey=${apiKey.take(6)}...")
    }

    override suspend fun translate(
        text: String,
        targetLang: String,
        sourceLang: String?,
    ): NativeTranslationResult = withContext(Dispatchers.IO) {
        if (apiKey.isBlank()) {
            throw Exception("translation.auth_failed: apiKey not configured")
        }

        val urlBuilder = "$BASE_URL/translate".toHttpUrl().newBuilder()
            .addQueryParameter("api-version", "3.0")
            .addQueryParameter("to", normalizeLang(targetLang) ?: targetLang)
        if (!sourceLang.isNullOrBlank()) {
            urlBuilder.addQueryParameter("from", normalizeLang(sourceLang) ?: sourceLang)
        }

        val body = JSONArray().put(JSONObject().put("Text", text))

        val request = Request.Builder()
            .url(urlBuilder.build())
            .post(body.toString().toRequestBody("application/json".toMediaType()))
            .header("Ocp-Apim-Subscription-Key", apiKey)
            .header("Ocp-Apim-Subscription-Region", region)
            .header("Content-Type", "application/json")
            .build()

        val response = client.newCall(request).execute()
        if (!response.isSuccessful) {
            throw Exception("Azure Translator error: ${response.code} ${response.body?.string()?.take(200)}")
        }

        val raw = response.body?.string() ?: "[]"
        val arr = JSONArray(raw)
        if (arr.length() == 0) throw Exception("Azure Translator: empty response")
        val first = arr.getJSONObject(0)
        val translations = first.optJSONArray("translations")
            ?: throw Exception("Azure Translator: no translations field")
        if (translations.length() == 0) throw Exception("Azure Translator: no translations returned")
        val t = translations.getJSONObject(0)

        val detected = first.optJSONObject("detectedLanguage")
        NativeTranslationResult(
            sourceText = text,
            translatedText = t.optString("text", ""),
            sourceLanguage = detected?.optString("language", sourceLang ?: "auto") ?: (sourceLang ?: "auto"),
            targetLanguage = t.optString("to", targetLang),
        )
    }

    override fun release() {}

    /**
     * 把上层的语言代号统一成 Azure Translator 的 BCP-47：
     *  - ZH / zh / zh-CN → zh-Hans
     *  - ZH-TW / zh-TW   → zh-Hant
     *  - EN / en / en-US → en
     * 已经是合法 BCP-47 的直接透传。
     */
    private fun normalizeLang(code: String?): String? {
        if (code.isNullOrBlank()) return code
        val c = code.trim()
        return when (c.uppercase()) {
            "ZH", "ZH-CN", "ZH-HANS" -> "zh-Hans"
            "ZH-TW", "ZH-HK", "ZH-HANT" -> "zh-Hant"
            "EN", "EN-US", "EN-GB" -> "en"
            "JA", "JA-JP" -> "ja"
            "KO", "KO-KR" -> "ko"
            "FR", "FR-FR" -> "fr"
            "DE", "DE-DE" -> "de"
            "ES", "ES-ES" -> "es"
            "RU", "RU-RU" -> "ru"
            "AR" -> "ar"
            "PT", "PT-PT" -> "pt-pt"
            "PT-BR" -> "pt"
            "IT" -> "it"
            "TH" -> "th"
            "VI" -> "vi"
            "ID" -> "id"
            "TR" -> "tr"
            else -> c
        }
    }
}
