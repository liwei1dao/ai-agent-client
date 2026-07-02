/// 默认实现：规则重要性 + 模板起草（离线可跑）。生产用 LLM 版替换同名端口。
library;

import 'models.dart';
import 'ports.dart';

/// 规则重要性：VIP 发件人 / 关键词命中 → high。
class RuleImportanceJudge implements ImportanceJudge {
  final List<String> vipSenders;
  final List<String> keywords;
  const RuleImportanceJudge({
    this.vipSenders = const ['张总', '老板', '老师', '总监', 'CEO'],
    this.keywords = const ['合同', '紧急', '面试', '付款', '截止', '尽快', 'urgent'],
  });

  @override
  Future<(Importance, String)> judge(Email e) async {
    for (final v in vipSenders) {
      if (e.sender.contains(v)) return (Importance.high, '重要发件人：$v');
    }
    for (final k in keywords) {
      if (e.subject.contains(k) || e.body.contains(k)) return (Importance.high, '含关键词：$k');
    }
    return (Importance.normal, '普通');
  }
}

/// 模板起草（占位）；生产用 llm_openai 的 ReplyDrafter 替换。
class TemplateReplyDrafter implements ReplyDrafter {
  const TemplateReplyDrafter();
  @override
  Future<String> draft(Email e, String instruction) async {
    final content = instruction.isEmpty ? '收到，稍后回复。' : instruction;
    return '${e.sender}您好：\n\n$content\n\n（由 UniHelper 代拟，发送前经你确认）';
  }
}
