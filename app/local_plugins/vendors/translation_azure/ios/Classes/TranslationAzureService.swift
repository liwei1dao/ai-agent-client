import Foundation
import ai_plugin_interface

/// Microsoft / Azure Translator v3.0 translation service.
public final class TranslationAzureService: NativeTranslationService {
    private static let baseUrl = "https://api.cognitive.microsofttranslator.com"

    private var apiKey: String = ""
    private var region: String = "global"

    public init() {}

    public func initialize(configJson: String) {
        guard let data = configJson.data(using: .utf8),
              let cfg = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        apiKey = (cfg["apiKey"] as? String) ?? ""
        let r = (cfg["region"] as? String) ?? ""
        if !r.isEmpty { region = r }
    }

    public func translate(
        text: String,
        targetLang: String,
        sourceLang: String?
    ) async throws -> NativeTranslationResult {
        guard !apiKey.isEmpty else {
            throw TranslationException(code: "auth_failed", message: "apiKey not configured")
        }

        var components = URLComponents(string: "\(Self.baseUrl)/translate")
        components?.queryItems = [
            URLQueryItem(name: "api-version", value: "3.0"),
            URLQueryItem(name: "to", value: normalizeLang(targetLang) ?? targetLang),
        ]
        if let src = sourceLang, !src.isEmpty {
            components?.queryItems?.append(
                URLQueryItem(name: "from", value: normalizeLang(src) ?? src)
            )
        }
        guard let url = components?.url else {
            throw TranslationException(code: "invalid_url", message: "bad Azure endpoint")
        }

        let body: [[String: Any]] = [["Text": text]]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue(region, forHTTPHeaderField: "Ocp-Apim-Subscription-Region")
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
                message: "Azure Translator error: \(http.statusCode) \(preview)"
            )
        }

        guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = arr.first,
              let translations = first["translations"] as? [[String: Any]],
              let t = translations.first else {
            throw TranslationException(code: "parse_error",
                                       message: "Azure Translator: unexpected response")
        }
        let translated = (t["text"] as? String) ?? ""
        let to = (t["to"] as? String) ?? targetLang
        let detected: String = {
            if let dl = first["detectedLanguage"] as? [String: Any],
               let lang = dl["language"] as? String {
                return lang
            }
            return sourceLang ?? "auto"
        }()

        return NativeTranslationResult(
            sourceText: text,
            translatedText: translated,
            sourceLanguage: detected,
            targetLanguage: to
        )
    }

    public func release() {}

    /// Canonical → Azure Translator BCP-47.
    private func normalizeLang(_ code: String?) -> String? {
        guard let raw = code?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return code }
        switch raw.uppercased() {
        case "ZH", "ZH-CN", "ZH-HANS":    return "zh-Hans"
        case "ZH-TW", "ZH-HK", "ZH-HANT": return "zh-Hant"
        case "EN", "EN-US", "EN-GB":      return "en"
        case "JA", "JA-JP":               return "ja"
        case "KO", "KO-KR":               return "ko"
        case "FR", "FR-FR":               return "fr"
        case "DE", "DE-DE":               return "de"
        case "ES", "ES-ES":               return "es"
        case "RU", "RU-RU":               return "ru"
        case "AR":                        return "ar"
        case "PT", "PT-PT":               return "pt-pt"
        case "PT-BR":                     return "pt"
        case "IT":                        return "it"
        case "TH":                        return "th"
        case "VI":                        return "vi"
        case "ID":                        return "id"
        case "TR":                        return "tr"
        default:                          return raw
        }
    }
}
