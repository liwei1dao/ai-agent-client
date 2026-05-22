import Foundation
import CommonCrypto
import ai_plugin_interface

/// Volcengine machine-translation service (`open.volcengineapi.com`,
/// `TranslateText` action, signed with Volcengine Signature V4 / HMAC-SHA256).
///
/// Config keys: `accessKeyId`, `secretAccessKey`, `region` (default `cn-north-1`).
public final class TranslationVolcengineService: NativeTranslationService {
    private static let host = "open.volcengineapi.com"
    private static let service = "translate"
    private static let action = "TranslateText"
    private static let version = "2020-06-01"
    private static let defaultRegion = "cn-north-1"

    private var accessKeyId: String = ""
    private var secretAccessKey: String = ""
    private var region: String = defaultRegion

    public init() {}

    public func initialize(configJson: String) {
        guard let data = configJson.data(using: .utf8),
              let cfg = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        accessKeyId = ((cfg["accessKeyId"] as? String) ?? "")
            .trimmingCharacters(in: .whitespaces)
        secretAccessKey = ((cfg["secretAccessKey"] as? String) ?? "")
            .trimmingCharacters(in: .whitespaces)
        // Tolerate apiKey written as "{accessKeyId}:{secretAccessKey}".
        if accessKeyId.isEmpty || secretAccessKey.isEmpty {
            let apiKey = (cfg["apiKey"] as? String) ?? ""
            let parts = apiKey.split(separator: ":", maxSplits: 1,
                                     omittingEmptySubsequences: false)
            if parts.count == 2 {
                accessKeyId = String(parts[0]).trimmingCharacters(in: .whitespaces)
                secretAccessKey = String(parts[1]).trimmingCharacters(in: .whitespaces)
            }
        }
        if let r = (cfg["region"] as? String)?.trimmingCharacters(in: .whitespaces),
           !r.isEmpty {
            region = r
        }
    }

    public func translate(
        text: String,
        targetLang: String,
        sourceLang: String?
    ) async throws -> NativeTranslationResult {
        if accessKeyId.isEmpty || secretAccessKey.isEmpty {
            throw TranslationException(code: "translation.auth_failed",
                                       message: "accessKeyId/secretAccessKey not configured")
        }

        let from = toVolcLang(sourceLang)
        let to = toVolcLang(targetLang) ?? targetLang

        let bodyObj: [String: Any] = [
            "SourceLanguage": from ?? "", // empty → auto-detect
            "TargetLanguage": to,
            "TextList": [text],
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: bodyObj)
        let body = String(data: bodyData, encoding: .utf8) ?? "{}"

        guard let url = URL(string:
            "https://\(Self.host)/?Action=\(Self.action)&Version=\(Self.version)") else {
            throw TranslationException(code: "translation.invalid_url",
                                       message: "bad Volcengine translate URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body.data(using: .utf8)
        for (k, v) in signedHeaders(body: body) {
            request.setValue(v, forHTTPHeaderField: k)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]

        if let apiError = (json["ResponseMetadata"] as? [String: Any])?["Error"]
            as? [String: Any] {
            let code = (apiError["Code"] as? String) ?? "api_error"
            let message = (apiError["Message"] as? String) ?? "Volcengine translate error"
            throw TranslationException(code: "translation.\(code)", message: message)
        }
        if let http = response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            throw TranslationException(code: "translation.http_\(http.statusCode)",
                                       message: "Volcengine translate HTTP \(http.statusCode)")
        }

        guard let list = json["TranslationList"] as? [[String: Any]],
              let first = list.first else {
            throw TranslationException(code: "translation.empty_response",
                                       message: "empty TranslationList")
        }
        let detected = (first["DetectedSourceLanguage"] as? String) ?? ""

        return NativeTranslationResult(
            sourceText: text,
            translatedText: (first["Translation"] as? String) ?? "",
            sourceLanguage: detected.isEmpty ? (from ?? "auto") : detected,
            targetLanguage: to
        )
    }

    public func release() {}

    // ── Volcengine Signature V4 ───────────────────────────────────────

    /// Builds the signed request headers (including `Authorization`).
    private func signedHeaders(body: String) -> [String: String] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        let xDate = formatter.string(from: Date())
        let shortDate = String(xDate.prefix(8))

        let payloadHash = sha256Hex(Data(body.utf8))
        let canonicalQuery = "Action=\(Self.action)&Version=\(Self.version)"

        let canonicalHeaders = "content-type:application/json\n"
            + "host:\(Self.host)\n"
            + "x-content-sha256:\(payloadHash)\n"
            + "x-date:\(xDate)\n"
        let signedHeaders = "content-type;host;x-content-sha256;x-date"

        let canonicalRequest = [
            "POST",
            "/",
            canonicalQuery,
            canonicalHeaders,
            signedHeaders,
            payloadHash,
        ].joined(separator: "\n")

        let credentialScope = "\(shortDate)/\(region)/\(Self.service)/request"
        let stringToSign = [
            "HMAC-SHA256",
            xDate,
            credentialScope,
            sha256Hex(Data(canonicalRequest.utf8)),
        ].joined(separator: "\n")

        let signature = hex(hmacSha256(signingKey(shortDate: shortDate),
                                       Data(stringToSign.utf8)))
        let authorization = "HMAC-SHA256 "
            + "Credential=\(accessKeyId)/\(credentialScope), "
            + "SignedHeaders=\(signedHeaders), "
            + "Signature=\(signature)"

        return [
            "Content-Type": "application/json",
            "X-Date": xDate,
            "X-Content-Sha256": payloadHash,
            "Authorization": authorization,
        ]
    }

    /// kSigning = HMAC(HMAC(HMAC(HMAC(SK, date), region), service), "request")
    private func signingKey(shortDate: String) -> Data {
        let kDate = hmacSha256(Data(secretAccessKey.utf8), Data(shortDate.utf8))
        let kRegion = hmacSha256(kDate, Data(region.utf8))
        let kService = hmacSha256(kRegion, Data(Self.service.utf8))
        return hmacSha256(kService, Data("request".utf8))
    }

    private func sha256Hex(_ data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash) }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private func hmacSha256(_ key: Data, _ message: Data) -> Data {
        var mac = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        key.withUnsafeBytes { keyBytes in
            message.withUnsafeBytes { msgBytes in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256),
                       keyBytes.baseAddress, key.count,
                       msgBytes.baseAddress, message.count,
                       &mac)
            }
        }
        return Data(mac)
    }

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    /// canonical → Volcengine translate language code (ISO 639-1 + Chinese variants).
    private func toVolcLang(_ code: String?) -> String? {
        guard let raw = code?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
            return nil
        }
        switch raw.uppercased() {
        case "AUTO":                      return nil
        case "ZH", "ZH-CN", "ZH-HANS":    return "zh"
        case "ZH-TW", "ZH-HK", "ZH-HANT": return "zh-Hant"
        default:
            return raw.split(separator: "-").first.map { String($0).lowercased() }
                ?? raw.lowercased()
        }
    }
}
