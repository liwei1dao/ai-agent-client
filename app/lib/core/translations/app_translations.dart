import 'package:get/get.dart';

import 'language/zh_cn.dart';

/// 简化版 GetX 翻译表 — 只支持简体中文，所有 locale 都映射到 zhCN。
/// 业务里大量使用 `'someKey'.tr`，这里把全部 .tr 调用统一返回中文。
class AppTranslations extends Translations {
  @override
  Map<String, Map<String, String>> get keys => {
        'zh_CN': zhCN,
        // 其他 locale 映射到中文，避免在非中文环境下显示英文 key
        'en_US': zhCN,
        'zh_HK': zhCN,
        'zh_TW': zhCN,
      };
}
