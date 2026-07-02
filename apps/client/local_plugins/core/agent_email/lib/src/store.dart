/// 邮件存储端口。默认内存；移动端注入 local_db DAO（去重/处理状态持久化）。
library;

import 'models.dart';

abstract interface class EmailStore {
  Future<void> putRecord(EmailRecord r);
  Future<List<EmailRecord>> records();
  Future<bool> isProcessed(String id);
  Future<void> markProcessed(String id);
  Future<void> setAction(String emailId, String action);
}

class InMemoryEmailStore implements EmailStore {
  final List<EmailRecord> _records = [];
  final Set<String> _processed = {};

  @override
  Future<void> putRecord(EmailRecord r) async => _records.insert(0, r);
  @override
  Future<List<EmailRecord>> records() async => List.of(_records);
  @override
  Future<bool> isProcessed(String id) async => _processed.contains(id);
  @override
  Future<void> markProcessed(String id) async => _processed.add(id);
  @override
  Future<void> setAction(String emailId, String action) async {
    for (final r in _records) {
      if (r.email.id == emailId) r.action = action;
    }
  }
}
