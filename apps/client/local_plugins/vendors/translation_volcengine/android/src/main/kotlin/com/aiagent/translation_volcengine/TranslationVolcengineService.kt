package com.aiagent.translation_volcengine

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
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * TranslationVolcengineService — 火山引擎机器翻译 API 原生实现
 *
 * 调用火山引擎 OpenAPI 网关的 `TranslateText` 接口，使用火山引擎签名 V4
 * （HMAC-SHA256）鉴权。
 */
class TranslationVolcengineService : NativeTranslationService {

    companion object {
        private const val TAG = "TranslationVolcengine"
        private const val HOST = "open.volcengineapi.com"
        private const val SERVICE = "translate"
        private const val ACTION = "TranslateText"
        private const val VERSION = "2020-06-01"
        private const val DEFAULT_REGION = "cn-north-1"
    }

    private val client = OkHttpClient()
    private var accessKeyId: String = ""
    private var secretAccessKey: String = ""
    private var region: String = DEFAULT_REGION

    override fun initialize(configJson: String) {
        val cfg = JSONObject(configJson)
        accessKeyId = cfg.optString("accessKeyId", "")
        secretAccessKey = cfg.optString("secretAccessKey", "")
        // 兼容 apiKey 写成 "{accessKeyId}:{secretAccessKey}" 的形式。
        if ((accessKeyId.isEmpty() || secretAccessKey.isEmpty())) {
            val apiKey = cfg.optString("apiKey", "")
            if (apiKey.contains(":")) {
                val parts = apiKey.split(":")
                accessKeyId = parts.getOrElse(0) { "" }.trim()
                secretAccessKey = parts.getOrElse(1) { "" }.trim()
            }
        }
        cfg.optString("region", "").trim().takeIf { it.isNotEmpty() }?.let { region = it }
        Log.d(TAG, "initialize: accessKeyId=${accessKeyId.take(8)}... region=$region")
    }

    override suspend fun translate(
        text: String,
        targetLang: String,
        sourceLang: String?,
    ): NativeTranslationResult = withContext(Dispatchers.IO) {
        if (accessKeyId.isEmpty() || secretAccessKey.isEmpty()) {
            throw Exception("translation.auth_failed: accessKeyId/secretAccessKey not configured")
        }

        val from = toVolcLang(sourceLang)
        val to = toVolcLang(targetLang) ?: targetLang

        val body = JSONObject()
            .put("SourceLanguage", from ?: "") // 空字符串 → 自动检测
            .put("TargetLanguage", to)
            .put("TextList", JSONArray().put(text))
            .toString()

        val request = Request.Builder()
            .url("https://$HOST/?Action=$ACTION&Version=$VERSION")
            .post(body.toRequestBody("application/json".toMediaType()))
            .apply { signedHeaders(body).forEach { (k, v) -> header(k, v) } }
            .build()

        val response = client.newCall(request).execute()
        val decoded = JSONObject(response.body?.string() ?: "{}")

        val apiError = decoded.optJSONObject("ResponseMetadata")?.optJSONObject("Error")
        if (apiError != null) {
            throw Exception(
                "Volcengine translate error: " +
                    "${apiError.optString("Code")} ${apiError.optString("Message")}"
            )
        }
        if (!response.isSuccessful) {
            throw Exception("Volcengine translate HTTP ${response.code}")
        }

        val list = decoded.optJSONArray("TranslationList")
        if (list == null || list.length() == 0) {
            throw Exception("Volcengine translate: empty TranslationList")
        }
        val first = list.getJSONObject(0)
        val detected = first.optString("DetectedSourceLanguage", "")

        NativeTranslationResult(
            sourceText = text,
            translatedText = first.optString("Translation", ""),
            sourceLanguage = detected.ifEmpty { from ?: "auto" },
            targetLanguage = to,
        )
    }

    override fun release() {}

    // ── 火山引擎签名 V4 ──────────────────────────────────────────────────

    /** 构造已签名的请求头（含 Authorization）。 */
    private fun signedHeaders(body: String): Map<String, String> {
        val sdf = SimpleDateFormat("yyyyMMdd'T'HHmmss'Z'", Locale.US)
        sdf.timeZone = TimeZone.getTimeZone("UTC")
        val xDate = sdf.format(java.util.Date())
        val shortDate = xDate.substring(0, 8)

        val payloadHash = sha256Hex(body.toByteArray(Charsets.UTF_8))
        val canonicalQuery = "Action=$ACTION&Version=$VERSION"

        val canonicalHeaders = "content-type:application/json\n" +
            "host:$HOST\n" +
            "x-content-sha256:$payloadHash\n" +
            "x-date:$xDate\n"
        val signedHeaders = "content-type;host;x-content-sha256;x-date"

        val canonicalRequest = listOf(
            "POST",
            "/",
            canonicalQuery,
            canonicalHeaders,
            signedHeaders,
            payloadHash,
        ).joinToString("\n")

        val credentialScope = "$shortDate/$region/$SERVICE/request"
        val stringToSign = listOf(
            "HMAC-SHA256",
            xDate,
            credentialScope,
            sha256Hex(canonicalRequest.toByteArray(Charsets.UTF_8)),
        ).joinToString("\n")

        val signature = hex(hmacSha256(signingKey(shortDate), stringToSign))
        val authorization = "HMAC-SHA256 " +
            "Credential=$accessKeyId/$credentialScope, " +
            "SignedHeaders=$signedHeaders, " +
            "Signature=$signature"

        return mapOf(
            "Content-Type" to "application/json",
            "X-Date" to xDate,
            "X-Content-Sha256" to payloadHash,
            "Authorization" to authorization,
        )
    }

    /** kSigning = HMAC(HMAC(HMAC(HMAC(SK, date), region), service), "request") */
    private fun signingKey(shortDate: String): ByteArray {
        val kDate = hmacSha256(secretAccessKey.toByteArray(Charsets.UTF_8), shortDate)
        val kRegion = hmacSha256(kDate, region)
        val kService = hmacSha256(kRegion, SERVICE)
        return hmacSha256(kService, "request")
    }

    private fun hmacSha256(key: ByteArray, data: String): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(key, "HmacSHA256"))
        return mac.doFinal(data.toByteArray(Charsets.UTF_8))
    }

    private fun sha256Hex(data: ByteArray): String =
        hex(MessageDigest.getInstance("SHA-256").digest(data))

    private fun hex(bytes: ByteArray): String =
        bytes.joinToString("") { "%02x".format(it) }

    /** canonical → 火山引擎翻译语言码（ISO 639-1 短码 + 中文变体）。 */
    private fun toVolcLang(code: String?): String? {
        if (code.isNullOrBlank()) return null
        return when (code.trim().uppercase()) {
            "AUTO" -> null
            "ZH", "ZH-CN", "ZH-HANS" -> "zh"
            "ZH-TW", "ZH-HK", "ZH-HANT" -> "zh-Hant"
            else -> code.substringBefore("-").lowercase()
        }
    }
}
