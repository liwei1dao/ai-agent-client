package com.aiagent.translation_aliyun

import android.util.Log
import com.aiagent.plugin_interface.NativeTranslationResult
import com.aiagent.plugin_interface.NativeTranslationService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.net.URLEncoder
import java.security.SecureRandom
import java.text.SimpleDateFormat
import java.util.*
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * TranslationAliyunService — 阿里云机器翻译 API 原生实现
 *
 * 使用阿里云通用版翻译 API（mt.aliyuncs.com），HMAC-SHA1 签名。
 */
class TranslationAliyunService : NativeTranslationService {

    companion object {
        private const val TAG = "TranslationAliyunSvc"
    }

    private val client = OkHttpClient()
    private var accessKeyId: String = ""
    private var accessKeySecret: String = ""

    override fun initialize(configJson: String) {
        val cfg = JSONObject(configJson)
        val apiKey = cfg.optString("apiKey", "")
        // apiKey format: "{accessKeyId}:{accessKeySecret}"
        val parts = apiKey.split(":")
        accessKeyId = parts.getOrElse(0) { "" }
        accessKeySecret = parts.getOrElse(1) { "" }
        Log.d(TAG, "initialize: accessKeyId=${accessKeyId.take(8)}...")
    }

    override suspend fun translate(
        text: String,
        targetLang: String,
        sourceLang: String?,
    ): NativeTranslationResult = withContext(Dispatchers.IO) {
        val params = buildParams(text, targetLang, sourceLang)
        val signature = sign(params)
        params["Signature"] = signature

        val queryString = params.entries.joinToString("&") { (k, v) ->
            "${URLEncoder.encode(k, "UTF-8")}=${URLEncoder.encode(v, "UTF-8")}"
        }

        val request = Request.Builder()
            .url("https://mt.aliyuncs.com/?$queryString")
            .get()
            .build()

        val response = client.newCall(request).execute()
        if (!response.isSuccessful) {
            throw Exception("Aliyun MT error: ${response.code}")
        }

        val json = JSONObject(response.body?.string() ?: "{}")
        val data = json.optJSONObject("Data")
        val translated = data?.optString("Translated", "") ?: ""

        NativeTranslationResult(
            sourceText = text,
            translatedText = translated,
            sourceLanguage = toAliyunLang(sourceLang) ?: "auto",
            targetLanguage = toAliyunLang(targetLang) ?: targetLang,
        )
    }

    override fun release() {}

    private fun buildParams(text: String, targetLang: String, sourceLang: String?): MutableMap<String, String> {
        val sdf = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)
        sdf.timeZone = TimeZone.getTimeZone("UTC")

        return mutableMapOf(
            "Action" to "TranslateGeneral",
            "Version" to "2018-10-12",
            "AccessKeyId" to accessKeyId,
            "SignatureMethod" to "HMAC-SHA1",
            "SignatureNonce" to randomNonce(),
            "SignatureVersion" to "1.0",
            "Timestamp" to sdf.format(Date()),
            "Format" to "JSON",
            "SourceLanguage" to (toAliyunLang(sourceLang) ?: "auto"),
            "TargetLanguage" to (toAliyunLang(targetLang) ?: targetLang),
            "SourceText" to text,
            "Scene" to "general",
        )
    }

    /** canonical → 阿里云机器翻译语言码（ISO 639-1 短码 + zh/zh-tw 等中文变体）。*/
    private fun toAliyunLang(code: String?): String? {
        if (code.isNullOrBlank()) return null
        return when (code.trim().uppercase()) {
            "AUTO" -> "auto"
            "ZH", "ZH-CN", "ZH-HANS" -> "zh"
            "ZH-TW", "ZH-HK", "ZH-HANT" -> "zh-tw"
            else -> code.substringBefore("-").lowercase()
        }
    }

    private fun sign(params: Map<String, String>): String {
        val sorted = params.keys.sorted()
        val canonical = sorted.joinToString("&") { k ->
            "${percentEncode(k)}=${percentEncode(params[k]!!)}"
        }
        val stringToSign = "GET&${percentEncode("/")}&${percentEncode(canonical)}"

        val mac = Mac.getInstance("HmacSHA1")
        mac.init(SecretKeySpec("$accessKeySecret&".toByteArray(Charsets.UTF_8), "HmacSHA1"))
        val rawHmac = mac.doFinal(stringToSign.toByteArray(Charsets.UTF_8))
        return Base64.getEncoder().encodeToString(rawHmac)
    }

    private fun percentEncode(value: String): String =
        URLEncoder.encode(value, "UTF-8")
            .replace("+", "%20")
            .replace("*", "%2A")
            .replace("%7E", "~")

    private fun randomNonce(): String {
        val bytes = ByteArray(16)
        SecureRandom().nextBytes(bytes)
        return bytes.joinToString("") { "%02x".format(it) }
    }
}
