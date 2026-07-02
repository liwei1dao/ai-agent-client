/// 默认实现：规则分类 + 规则建议（离线可跑）。生产可换 LLM 版。
library;

import 'models.dart';
import 'ports.dart';

class RuleCategorizer implements Categorizer {
  final Map<String, List<String>> rules;
  const RuleCategorizer([this.rules = const {
        '餐饮': ['饭', '餐', '外卖', '咖啡', '奶茶', '零食', '吃', '午饭', '晚饭', '早饭'],
        '交通': ['打车', '地铁', '公交', '加油', '停车', '高铁', '机票', '出租', '滴滴'],
        '购物': ['买', '淘宝', '京东', '衣服', '鞋', '数码', '化妆'],
        '居住': ['房租', '水电', '物业', '燃气', '宽带'],
        '娱乐': ['电影', '游戏', '演唱会', '门票', 'ktv'],
        '医疗': ['药', '医院', '挂号', '体检'],
        '收入': ['工资', '报销', '奖金', '进账', '到账', '收入'],
      }]);

  @override
  String categoryOf(String text) {
    final t = text.toLowerCase();
    for (final e in rules.entries) {
      if (e.value.any((k) => t.contains(k.toLowerCase()))) return e.key;
    }
    return '其他';
  }
}

class RuleAdvicePlanner implements AdvicePlanner {
  const RuleAdvicePlanner();
  @override
  String advise(MonthReport r) {
    final over = r.overBudget;
    if (over.isNotEmpty) {
      return '${over.join('、')} 已超预算，建议本月剩余控制开销；其余分类正常。';
    }
    if (r.balance > 0) {
      return '本月结余 ¥${r.balance.toStringAsFixed(0)}，节奏健康，可考虑转入储蓄。';
    }
    return '本月支出已超收入，建议复盘大额开销。';
  }
}
