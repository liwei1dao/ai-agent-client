import 'package:flutter_riverpod/flutter_riverpod.dart';

final localeServiceProvider = Provider((ref) => LocaleService());

class LocaleService {
  static const langNames = <String, String>{
    'auto': '自动检测',
    'zh': '中文',
    'en': 'English',
    'ja': '日本語',
    'ko': '한국어',
    'fr': 'Français',
    'de': 'Deutsch',
    'es': 'Español',
    'ru': 'Русский',
    'ar': 'العربية',
    'pt': 'Português',
  };

  static const allCodes = [
    'zh', 'en', 'ja', 'ko', 'fr', 'de', 'es', 'ru', 'ar', 'pt',
  ];

  String displayName(String code) => langNames[code] ?? code;
}
