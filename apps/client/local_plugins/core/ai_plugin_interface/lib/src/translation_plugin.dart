/// 翻译结果
class TranslationResult {
  const TranslationResult({
    required this.sourceText,
    required this.translatedText,
    required this.sourceLanguage,
    required this.targetLanguage,
  });

  final String sourceText;
  final String translatedText;
  final String sourceLanguage;
  final String targetLanguage;
}

/// 翻译插件抽象接口（每条消息独立翻译，无打断机制）
abstract class TranslationPlugin {
  /// 初始化
  Future<void> initialize({required String apiKey, Map<String, String> extra = const {}});

  /// 翻译文本（每次调用独立，不关联 requestId）
  Future<TranslationResult> translate({
    required String text,
    required String targetLanguage,
    String? sourceLanguage,
  });

  /// 释放资源
  Future<void> dispose();
}
