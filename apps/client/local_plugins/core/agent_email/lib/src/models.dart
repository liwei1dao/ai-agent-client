library;

enum Importance { high, normal, low }

class Email {
  final String id; // messageId（去重）
  final String account;
  final String sender; // 显示名
  final String address; // 邮箱地址
  final String subject;
  final String body;
  final DateTime receivedAt;
  const Email({
    required this.id,
    required this.account,
    required this.sender,
    required this.address,
    required this.subject,
    required this.body,
    required this.receivedAt,
  });
}

class Draft {
  final String id;
  final String to;
  final String subject;
  final String body;
  final String? inReplyTo;
  const Draft({
    required this.id,
    required this.to,
    required this.subject,
    required this.body,
    this.inReplyTo,
  });
}

/// 一封邮件的处理记录。
class EmailRecord {
  final Email email;
  final Importance importance;
  final String reason;
  String action; // none | notified | replied
  EmailRecord(this.email, this.importance, this.reason, {this.action = 'none'});
}
