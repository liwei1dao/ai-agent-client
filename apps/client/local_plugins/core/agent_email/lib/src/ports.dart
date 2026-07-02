/// 端口：把邮箱接入 / 重要性判定 / 起草 隔离，可换、可测。
library;

import 'models.dart';

/// 邮箱接入。默认实现留给平台：IMAP/SMTP（enough_mail）或 Gmail（OAuth/API/MCP）。
abstract interface class MailProvider {
  Future<List<Email>> fetchUnread({DateTime? since});
  Future<void> sendDraft(Draft draft);
  Future<void> markRead(String id);
}

/// 重要性判定（规则 / LLM）。
abstract interface class ImportanceJudge {
  /// 返回 (重要度, 理由)。
  Future<(Importance, String)> judge(Email email);
}

/// 回复起草（LLM）。默认模板实现见 defaults.dart。
abstract interface class ReplyDrafter {
  Future<String> draft(Email email, String instruction);
}
