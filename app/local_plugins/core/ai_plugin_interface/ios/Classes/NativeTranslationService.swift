import Foundation

/// Text-translation service contract.
///
/// Pure request/response — no events, no requestId, no interruption.
public protocol NativeTranslationService: AnyObject {
    func initialize(configJson: String)

    /// Translate `text` into `targetLang`. `sourceLang == nil` → auto-detect.
    func translate(text: String, targetLang: String, sourceLang: String?) async throws
        -> NativeTranslationResult

    func release()
}

public extension NativeTranslationService {
    func translate(text: String, targetLang: String) async throws -> NativeTranslationResult {
        try await translate(text: text, targetLang: targetLang, sourceLang: nil)
    }
}

public struct TranslationException: Error {
    public let code: String
    public let message: String
    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}
