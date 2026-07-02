library;

enum AuthType { oauth, token, imap, mcp, system }

enum ConnStatus { disconnected, connected, expired }

/// 连接器能喂给业务的能力（业务服务据此找到数据源）。
enum Feed { mail, calendar, tasks, messages, approval, tool, docs, health }

/// 一个第三方连接器（生活/工作生态里的一个可连接服务）。
class Connector {
  final String id;
  final String name;
  final AuthType authType;
  final Set<Feed> feeds;
  ConnStatus status;
  String? account; // 展示用（zhang@x.com / 组织名）
  List<String> scopes;
  String? credRef; // 凭据引用（真身在 CredentialVault，本地加密）

  Connector({
    required this.id,
    required this.name,
    required this.authType,
    required this.feeds,
    this.status = ConnStatus.disconnected,
    this.account,
    this.scopes = const [],
    this.credRef,
  });
}

/// 授权入参（不同 authType 用不同工厂）。fields 为待存入 vault 的密钥材料。
class AuthPayload {
  final Map<String, String> fields;
  final String? account;
  final List<String> scopes;
  const AuthPayload(this.fields, {this.account, this.scopes = const []});

  factory AuthPayload.token(String token, {String? account}) =>
      AuthPayload({'token': token}, account: account);

  factory AuthPayload.imap(String host, String user, String appPassword) =>
      AuthPayload({'host': host, 'user': user, 'appPassword': appPassword}, account: user);

  factory AuthPayload.oauth(String accessToken, {String? refreshToken, String? account, List<String> scopes = const []}) =>
      AuthPayload({'accessToken': accessToken, if (refreshToken != null) 'refreshToken': refreshToken},
          account: account, scopes: scopes);

  factory AuthPayload.mcp(String url, {Map<String, String> headers = const {}, String? name}) =>
      AuthPayload({'url': url, ...headers}, account: name);
}
