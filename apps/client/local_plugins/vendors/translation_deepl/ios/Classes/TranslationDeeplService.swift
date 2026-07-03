import Foundation
import ai_plugin_interface

/// DeepL API v2 translation service (iOS port).
public final class TranslationDeeplService: NativeTranslationService {
    private static let baseUrl = "https://api-free.deepl.com/v2"

    private var apiKey: String = ""

    public init() {}

    public func initialize(configJson: String) {
        guard let data = configJson.data(using: .utf8),
              let cfg = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        apiKey = (cfg["apiKey"] as? String) ?? ""
    }

    public func translate(
        text: String,
        targetLang: String,
        sourceLang: String?
    ) async throws -> NativeTranslationResult {
        guard let url = URL(string: "\(Self.baseUrl)/translate") else {
            throw TranslationException(code: "invalid_url", message: "bad DeepL endpoint")
        }
        var body: [String: Any] = [
            "text": [text],
            "target_lang": toDeeplTarget(targetLang),
        ]
        if let src = sourceLang, !toDeeplSource(src).isEmpty {
            body["source_lang"] = toDeeplSource(src)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("DeepL-Auth-Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranslationException(code: "no_response", message: "no HTTP response")
        }
        if !(200..<300).contains(http.statusCode) {
            let preview = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw TranslationException(
                code: "http_\(http.statusCode)",
                message: "DeepL API error: \(http.statusCode) \(preview)"
            )
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let translations = json["translations"] as? [[String: Any]],
              let first = translations.first,
              let translated = first["text"] as? String else {
            throw TranslationException(code: "parse_error", message: "unexpected DeepL response")
        }
        let detected = ((first["detected_source_language"] as? String)
                        ?? sourceLang ?? "auto").lowercased()
        return NativeTranslationResult(
            sourceText: text,
            translatedText: translated,
            sourceLanguage: detected,
            targetLanguage: targetLang
        )
    }

    public func release() {}

    // ── Language-code mapping ─────────────────────────────────────

    /// canonical (zh-CN / en-US / pt-BR …) → DeepL `target_lang`.
    private func toDeeplTarget(_ code: String) -> String {
        let upper = code.trimmingCharacters(in: .whitespaces).uppercased()
        switch upper {
        case "ZH", "ZH-CN", "ZH-HANS": return "ZH-HANS"
        case "ZH-TW", "ZH-HK", "ZH-HANT": return "ZH-HANT"
        case "EN", "EN-US": return "EN-US"
        case "EN-GB": return "EN-GB"
        case "PT", "PT-BR": return "PT-BR"
        case "PT-PT": return "PT-PT"
        default:
            return upper.split(separator: "-").first.map(String.init) ?? upper
        }
    }

    /// canonical → DeepL `source_lang`. `auto`/empty → "" (auto-detect).
    private func toDeeplSource(_ code: String) -> String {
        let upper = code.trimmingCharacters(in: .whitespaces).uppercased()
        if upper == "AUTO" || upper.isEmpty { return "" }
        return upper.split(separator: "-").first.map(String.init) ?? upper
    }
}
