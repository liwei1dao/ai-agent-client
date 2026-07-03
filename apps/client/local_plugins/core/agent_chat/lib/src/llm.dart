/// LLM 端口 + 可测默认实现。真模型（火山/OpenAI/本地）在框架层实现本接口注入。
library;

import 'messages.dart';

/// 大模型端口：给定完整消息序列（含 system/上下文/历史/本轮），流式产出回复分片。
abstract interface class LlmProvider {
  Stream<String> stream(List<ChatMessage> messages);
}

/// 回声实现：把用户最后一句原样带回。零依赖、确定性，供 web/desktop/测试兜底。
class EchoLlm implements LlmProvider {
  const EchoLlm();
  @override
  Stream<String> stream(List<ChatMessage> messages) async* {
    final last = messages.lastWhere((m) => m.role == Role.user,
        orElse: () => const ChatMessage.user(''));
    yield '收到：';
    yield last.text;
  }
}

/// 剧本实现：按「用户最后一句包含某关键词 → 固定回复」应答，便于自检断言。
class ScriptedLlm implements LlmProvider {
  final Map<String, String> script;
  final String fallback;
  const ScriptedLlm(this.script, {this.fallback = '嗯。'});
  @override
  Stream<String> stream(List<ChatMessage> messages) async* {
    final last = messages.lastWhere((m) => m.role == Role.user,
        orElse: () => const ChatMessage.user('')).text;
    for (final e in script.entries) {
      if (last.contains(e.key)) {
        yield e.value;
        return;
      }
    }
    yield fallback;
  }
}
