import 'package:get/get.dart';
import '../../data/services/network/dio_manager.dart';

/// 根据当前语言返回 doc 目录名，如 "zh_cn"、"en"、"fr"
String docLangPath() {
  final lang = Get.locale?.languageCode ?? 'en';
  final country = Get.locale?.countryCode?.toUpperCase() ?? '';
  if (lang == 'zh') {
    if (country == 'CN') return 'zh_cn';
    if (country == 'HK') return 'zh_hk';
    return 'zh_tw';
  }
  const supported = [
    'ar', 'bg', 'cs', 'da', 'de', 'el', 'es', 'et', 'fa', 'fi', 'fr',
    'hi', 'hr', 'hu', 'id', 'is', 'it', 'ja', 'ko', 'lt', 'lv', 'ms',
    'nb', 'nl', 'pl', 'pt', 'ro', 'ru', 'sk', 'sl', 'sr', 'sv', 'th',
    'tl', 'tr', 'uk', 'vi',
  ];
  return supported.contains(lang) ? lang : 'en';
}

/// 业务服务器上的法律文档目录前缀（按 docLangPath() 完整语言命中）
String _legalDocBase() => '${DioManager().baseUrl}/docs/legal/${docLangPath()}';

/// 会员协议仅有 zh_cn / zh_hk / zh_tw / en 四种文件，其余语言一律回退英文
String _memberAgreementLangDir() {
  final lang = Get.locale?.languageCode ?? 'en';
  if (lang == 'zh') {
    final country = Get.locale?.countryCode?.toUpperCase() ?? '';
    if (country == 'CN') return 'zh_cn';
    if (country == 'HK') return 'zh_hk';
    return 'zh_tw';
  }
  return 'en';
}

/// 构建隐私政策 URL（托管在业务服务器上）
String privacyPolicyUrl() => '${_legalDocBase()}/privacy_policy.html';

/// 构建用户协议 URL（托管在业务服务器上）
String userAgreementUrl() => '${_legalDocBase()}/user_agreement.html';

/// 构建会员服务协议 URL（托管在业务服务器上）
String memberServiceAgreementUrl() =>
    '${DioManager().baseUrl}/docs/legal/${_memberAgreementLangDir()}/member_service_agreement.html';
