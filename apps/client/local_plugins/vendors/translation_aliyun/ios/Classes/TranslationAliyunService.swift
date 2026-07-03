import Foundation
import CommonCrypto
import ai_plugin_interface

/// Aliyun MT translation service (`mt.aliyuncs.com`, HMAC-SHA1 signed).
///
/// Config: `apiKey` formatted as `"{accessKeyId}:{accessKeySecret}"`.
public final class TranslationAliyunService: NativeTranslationService {
    private var accessKeyId: String = ""
    private var accessKeySecret: String = ""

    public init() {}

    public func initialize(configJson: String) {
        guard let data = configJson.data(using: .utf8),
              let cfg = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        let apiKey = (cfg["apiKey"] as? String) ?? ""
        let parts = apiKey.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count == 2 {
            accessKeyId = String(parts[0])
            accessKeySecret = String(parts[1])
        } else {
            accessKeyId = parts.first.map(String.init) ?? ""
            accessKeySecret = ""
        }
    }

    public func translate(
        text: String,
        targetLang: String,
        sourceLang: String?
    ) async throws -> NativeTranslationResult {
        var params = buildParams(text: text, targetLang: targetLang, sourceLang: sourceLang)
        params["Signature"] = sign(params)

        // Build the query string in the same canonical encoding the signature
        // used; otherwise the gateway rejects with `IncompleteSignature`.
        let query = params.map { k, v in
            "\(percentEncode(k))=\(percentEncode(v))"
        }.joined(separator: "&")

        guard let url = URL(string: "https://mt.aliyuncs.com/?\(query)") else {
            throw TranslationException(code: "invalid_url", message: "bad Aliyun MT URL")
        }

        let request = URLRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranslationException(code: "no_response", message: "no HTTP response")
        }
        if !(200..<300).contains(http.statusCode) {
            throw TranslationException(code: "http_\(http.statusCode)",
                                       message: "Aliyun MT error: \(http.statusCode)")
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let translated = ((json["Data"] as? [String: Any])?["Translated"] as? String) ?? ""

        return NativeTranslationResult(
            sourceText: text,
            translatedText: translated,
            sourceLanguage: toAliyunLang(sourceLang) ?? "auto",
            targetLanguage: toAliyunLang(targetLang) ?? targetLang
        )
    }

    public func release() {}

    // ── Helpers ───────────────────────────────────────────────────

    private func buildParams(text: String, targetLang: String, sourceLang: String?) -> [String: String] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")

        return [
            "Action": "TranslateGeneral",
            "Version": "2018-10-12",
            "AccessKeyId": accessKeyId,
            "SignatureMethod": "HMAC-SHA1",
            "SignatureNonce": randomNonce(),
            "SignatureVersion": "1.0",
            "Timestamp": formatter.string(from: Date()),
            "Format": "JSON",
            "SourceLanguage": toAliyunLang(sourceLang) ?? "auto",
            "TargetLanguage": toAliyunLang(targetLang) ?? targetLang,
            "SourceText": text,
            "Scene": "general",
        ]
    }

    private func toAliyunLang(_ code: String?) -> String? {
        guard let raw = code?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        switch raw.uppercased() {
        case "AUTO":                       return "auto"
        case "ZH", "ZH-CN", "ZH-HANS":     return "zh"
        case "ZH-TW", "ZH-HK", "ZH-HANT":  return "zh-tw"
        default:
            return raw.split(separator: "-").first.map { String($0).lowercased() } ?? raw.lowercased()
        }
    }

    private func sign(_ params: [String: String]) -> String {
        let sortedKeys = params.keys.sorted()
        let canonical = sortedKeys.map { k in
            "\(percentEncode(k))=\(percentEncode(params[k] ?? ""))"
        }.joined(separator: "&")
        let stringToSign = "GET&\(percentEncode("/"))&\(percentEncode(canonical))"
        return hmacSha1Base64(stringToSign, key: "\(accessKeySecret)&")
    }

    private func percentEncode(_ value: String) -> String {
        // Aliyun signature requires RFC 3986 percent-encoding (the URL-form
        // variant used by `addingPercentEncoding(.urlQueryAllowed)` keeps `+`
        // and `*` unescaped, which breaks the signature).
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func hmacSha1Base64(_ string: String, key: String) -> String {
        let keyData = key.data(using: .utf8) ?? Data()
        let messageData = string.data(using: .utf8) ?? Data()
        var mac = Data(count: Int(CC_SHA1_DIGEST_LENGTH))
        mac.withUnsafeMutableBytes { macBytes -> Void in
            keyData.withUnsafeBytes { keyBytes in
                messageData.withUnsafeBytes { msgBytes in
                    CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA1),
                           keyBytes.baseAddress, keyData.count,
                           msgBytes.baseAddress, messageData.count,
                           macBytes.baseAddress)
                }
            }
        }
        return mac.base64EncodedString()
    }

    private func randomNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
