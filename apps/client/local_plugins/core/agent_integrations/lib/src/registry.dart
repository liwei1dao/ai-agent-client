/// 连接注册中心：授权/断开/刷新 + 按能力查已连接源（喂给业务服务）。
library;

import 'models.dart';
import 'ports.dart';

/// 默认第三方目录（生活↔工作）。可再动态 [IntegrationRegistry.addConnector]（如 MCP）。
List<Connector> defaultCatalog() => [
      Connector(id: 'email', name: '邮箱（IMAP/Gmail）', authType: AuthType.imap, feeds: {Feed.mail}),
      Connector(id: 'dingtalk', name: '钉钉', authType: AuthType.oauth, feeds: {Feed.tasks, Feed.calendar, Feed.messages, Feed.approval}),
      Connector(id: 'wecom', name: '企业微信', authType: AuthType.oauth, feeds: {Feed.messages, Feed.approval, Feed.calendar}),
      Connector(id: 'feishu', name: '飞书', authType: AuthType.oauth, feeds: {Feed.docs, Feed.calendar, Feed.messages}),
      Connector(id: 'syscal', name: '系统日历', authType: AuthType.system, feeds: {Feed.calendar}),
      Connector(id: 'gcal', name: 'Google Calendar', authType: AuthType.mcp, feeds: {Feed.calendar}),
    ];

class IntegrationRegistry {
  final ConnectionStore store;
  final CredentialVault vault;
  final Map<String, Connector> _connectors = {};

  IntegrationRegistry({ConnectionStore? store, CredentialVault? vault, List<Connector>? catalog})
      : store = store ?? InMemoryConnectionStore(),
        vault = vault ?? InMemoryCredentialVault() {
    for (final c in (catalog ?? defaultCatalog())) {
      _connectors[c.id] = c;
    }
  }

  List<Connector> list() => _connectors.values.toList();
  Connector? get(String id) => _connectors[id];

  /// 动态加入连接器（如用户添加一个 MCP 服务器）。
  void addConnector(Connector c) => _connectors[c.id] = c;

  /// 授权连接：密钥入保险箱，状态置 connected，持久化。
  Future<Connector> connect(String id, AuthPayload payload) async {
    final c = _connectors[id];
    if (c == null) throw StateError('未知连接器：$id');
    c.credRef = await vault.save(c.id, payload.fields);
    c.account = payload.account ?? c.account;
    if (payload.scopes.isNotEmpty) c.scopes = payload.scopes;
    c.status = ConnStatus.connected;
    await store.put(c);
    return c;
  }

  Future<void> disconnect(String id) async {
    final c = _connectors[id];
    if (c == null) return;
    if (c.credRef != null) await vault.delete(c.credRef!);
    c.credRef = null;
    c.account = null;
    c.status = ConnStatus.disconnected;
    await store.put(c);
  }

  /// token 过期 → 标记需重新授权（骨架）。
  Future<void> markExpired(String id) async {
    final c = _connectors[id];
    if (c == null) return;
    c.status = ConnStatus.expired;
    await store.put(c);
  }

  /// 取某连接器的凭据（业务服务据此构建端口实现，如 MailProvider）。
  Future<Map<String, String>?> credentialsOf(String id) async {
    final c = _connectors[id];
    if (c?.credRef == null) return null;
    return vault.load(c!.credRef!);
  }

  /// 已连接且能喂给某能力的连接器——业务服务据此找到数据源。
  List<Connector> feeding(Feed feed) => _connectors.values
      .where((c) => c.status == ConnStatus.connected && c.feeds.contains(feed))
      .toList();

  /// 从持久化恢复连接状态（跨会话）。
  Future<void> restore() async {
    for (final saved in await store.all()) {
      final c = _connectors[saved.id];
      if (c != null) {
        c.status = saved.status;
        c.account = saved.account;
        c.credRef = saved.credRef;
        c.scopes = saved.scopes;
      } else {
        _connectors[saved.id] = saved;
      }
    }
  }
}
