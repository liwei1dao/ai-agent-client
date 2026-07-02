/// 端口：连接状态持久化 + 凭据保险箱。默认内存；移动端注入 local_db + 平台钥匙串。
library;

import 'models.dart';

/// 连接状态持久化（connections 表）。凭据本身不在此，只存 credRef 引用。
abstract interface class ConnectionStore {
  Future<void> put(Connector c);
  Future<List<Connector>> all();
  Future<Connector?> get(String id);
}

/// 凭据保险箱：存密文，返回引用 credRef。移动端 = 平台钥匙串/加密存储。
abstract interface class CredentialVault {
  Future<String> save(String connectorId, Map<String, String> secret);
  Future<Map<String, String>?> load(String credRef);
  Future<void> delete(String credRef);
}

class InMemoryConnectionStore implements ConnectionStore {
  final Map<String, Connector> _m = {};
  @override
  Future<void> put(Connector c) async => _m[c.id] = c;
  @override
  Future<List<Connector>> all() async => _m.values.toList();
  @override
  Future<Connector?> get(String id) async => _m[id];
}

class InMemoryCredentialVault implements CredentialVault {
  final Map<String, Map<String, String>> _m = {};
  int _n = 0;
  @override
  Future<String> save(String connectorId, Map<String, String> secret) async {
    final ref = 'cred:$connectorId:${_n++}';
    _m[ref] = Map.of(secret);
    return ref;
  }

  @override
  Future<Map<String, String>?> load(String credRef) async => _m[credRef];
  @override
  Future<void> delete(String credRef) async => _m.remove(credRef);
}
