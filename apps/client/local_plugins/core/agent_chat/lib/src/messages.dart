/// 会话消息与多轮记忆。
library;

enum Role { system, user, assistant }

class ChatMessage {
  final Role role;
  final String text;
  const ChatMessage(this.role, this.text);
  const ChatMessage.user(this.text) : role = Role.user;
  const ChatMessage.assistant(this.text) : role = Role.assistant;
  const ChatMessage.system(this.text) : role = Role.system;
}

/// 一段多轮会话（按 sessionId 隔离）。history 只存 user/assistant 往返，
/// system/上下文每轮临时拼装，不入库。
class ConversationSession {
  final String id;
  final String? userId;
  final List<ChatMessage> history;
  ConversationSession(this.id, {this.userId, List<ChatMessage>? history})
      : history = history ?? [];

  void add(ChatMessage m) => history.add(m);

  /// 取最近 [turns] 轮（1 轮 = 一问一答，最多 2*turns 条）。
  List<ChatMessage> window(int turns) {
    final n = turns * 2;
    return history.length <= n ? List.of(history) : history.sublist(history.length - n);
  }
}

/// 会话存储端口。默认内存实现；移动端注入 local_db 后台可读（杀 app 仍在）。
abstract interface class SessionStore {
  Future<ConversationSession> load(String sessionId, {String? userId});
  Future<void> save(ConversationSession session);
}

class InMemorySessionStore implements SessionStore {
  final Map<String, ConversationSession> _m = {};
  @override
  Future<ConversationSession> load(String sessionId, {String? userId}) async =>
      _m[sessionId] ??= ConversationSession(sessionId, userId: userId);
  @override
  Future<void> save(ConversationSession session) async => _m[session.id] = session;
}
