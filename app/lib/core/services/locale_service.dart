import 'package:flutter_riverpod/flutter_riverpod.dart';

final localeServiceProvider = Provider((ref) => LocaleService());

/// 平台语言码中枢（canonical = BCP-47 with region，如 zh-CN / en-US）。
///
/// 约定：
///  - 整个 app（UI、Riverpod state、agent_config / service_config 落库）一律
///    使用 [allCodes] 中的 canonical 形式；
///  - 各 STT/TTS/Translation/AST 服务插件在自己内部把 canonical 映射为厂商方言；
///  - 读取旧库 / 外部输入时统一过 [toCanonical] 兜底。
class LocaleService {
  static const langNames = <String, String>{
    'auto': '自动检测',
    'zh-CN': '中文（简体）',
    'zh-TW': '中文（繁體）',
    'en-US': 'English',
    'ja-JP': '日本語',
    'ko-KR': '한국어',
    'fr-FR': 'Français',
    'de-DE': 'Deutsch',
    'es-ES': 'Español',
    'ru-RU': 'Русский',
    'ar-SA': 'العربية',
    'pt-BR': 'Português (Brasil)',
    'pt-PT': 'Português',
    'it-IT': 'Italiano',
    'th-TH': 'ไทย',
    'vi-VN': 'Tiếng Việt',
    'id-ID': 'Bahasa Indonesia',
    'tr-TR': 'Türkçe',
  };

  static const allCodes = [
    'zh-CN', 'en-US', 'ja-JP', 'ko-KR', 'fr-FR',
    'de-DE', 'es-ES', 'ru-RU', 'ar-SA', 'pt-BR',
  ];

  /// 把任意历史/松散形式的语言码归一到 canonical：
  ///  - 旧的小写 ISO 639-1（zh / en / ja）→ 加默认地区（zh-CN / en-US / ja-JP）
  ///  - 旧的两字大写代号（ZH / EN / JA）→ 同上
  ///  - 各种大小写写法（zh-cn / EN-us）→ canonical 大小写
  ///  - `auto` 透传
  ///  - 无法识别的原样返回（让上层服务再尝试）
  static String toCanonical(String? input) {
    if (input == null) return 'auto';
    final trimmed = input.trim();
    if (trimmed.isEmpty) return 'auto';
    final upper = trimmed.toUpperCase();
    switch (upper) {
      case 'AUTO':
        return 'auto';
      case 'ZH':
      case 'ZH-CN':
      case 'ZH-HANS':
      case 'CMN':
      case 'CMN-HANS':
        return 'zh-CN';
      case 'ZH-TW':
      case 'ZH-HK':
      case 'ZH-HANT':
        return 'zh-TW';
      case 'EN':
      case 'EN-US':
        return 'en-US';
      case 'EN-GB':
        return 'en-US';
      case 'JA':
      case 'JA-JP':
      case 'JP':
        return 'ja-JP';
      case 'KO':
      case 'KO-KR':
      case 'KR':
        return 'ko-KR';
      case 'FR':
      case 'FR-FR':
        return 'fr-FR';
      case 'DE':
      case 'DE-DE':
        return 'de-DE';
      case 'ES':
      case 'ES-ES':
        return 'es-ES';
      case 'RU':
      case 'RU-RU':
        return 'ru-RU';
      case 'AR':
      case 'AR-SA':
        return 'ar-SA';
      case 'PT':
      case 'PT-BR':
        return 'pt-BR';
      case 'PT-PT':
        return 'pt-PT';
      case 'IT':
      case 'IT-IT':
        return 'it-IT';
      case 'TH':
      case 'TH-TH':
        return 'th-TH';
      case 'VI':
      case 'VI-VN':
        return 'vi-VN';
      case 'ID':
      case 'ID-ID':
        return 'id-ID';
      case 'TR':
      case 'TR-TR':
        return 'tr-TR';
      default:
        // 已经是带地区且未知的写法，规范大小写：xx-YY
        if (trimmed.contains('-')) {
          final parts = trimmed.split('-');
          if (parts.length >= 2) {
            return '${parts[0].toLowerCase()}-${parts[1].toUpperCase()}';
          }
        }
        return trimmed;
    }
  }

  /// 批量归一。
  static List<String> toCanonicalAll(Iterable<String?> codes) =>
      codes.map(toCanonical).toList();

  String displayName(String code) =>
      langNames[code] ?? langNames[toCanonical(code)] ?? code;
}
