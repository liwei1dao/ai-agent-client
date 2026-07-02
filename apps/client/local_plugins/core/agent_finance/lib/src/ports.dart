/// 端口：分类 / 建议，可换（规则或 LLM）。
library;

import 'models.dart';

/// 把一笔消费的描述归类（餐饮/交通/购物/居住/…）。
abstract interface class Categorizer {
  String categoryOf(String text);
}

/// 基于月报给财务建议（规则或 LLM）。
abstract interface class AdvicePlanner {
  String advise(MonthReport report);
}
