/// 把"现有 agent"（对话/翻译/…）包成管家可调度的 [SpecialistAgent]，不改其基础模板。
library;

import 'models.dart';
import 'ports.dart';

/// 现有 agent 运行时的规约信号（对应底层 onLlmFirstToken/onLlmChunk/onToolCall/onDone/onError…）。
enum RunnerSignal { firstToken, chunk, toolCallStart, toolCallResult, done, error, needConfirm }

class RunnerEvent {
  final RunnerSignal signal;
  final String? text; // chunk 文本；或 done 的最终文本（可选）
  final String? toolName;
  final String? errorCode;
  final String? errorMessage;
  final Confirm? confirm;
  const RunnerEvent(
    this.signal, {
    this.text,
    this.toolName,
    this.errorCode,
    this.errorMessage,
    this.confirm,
  });

  static RunnerEvent chunk(String t) => RunnerEvent(RunnerSignal.chunk, text: t);
  static RunnerEvent done([String? t]) => RunnerEvent(RunnerSignal.done, text: t);
  static RunnerEvent error(String code, String msg) =>
      RunnerEvent(RunnerSignal.error, errorCode: code, errorMessage: msg);
  static RunnerEvent tool(String name) => RunnerEvent(RunnerSignal.toolCallStart, toolName: name);
  static RunnerEvent confirmNeeded(Confirm c) => RunnerEvent(RunnerSignal.needConfirm, confirm: c);
}

/// 把一次请求的运行规约为 [RunnerEvent] 流。
///
/// 由 app 用**现有 agent 的既有接口**实现（startSession/sendText + onLlmChunk/onLlmDone… →
/// 逐条 yield RunnerEvent），**不改基础模板 / NativeAgent 契约**。
abstract interface class LegacyAgentRunner {
  Stream<RunnerEvent> run(String text, {String? context, String? userId});
}

/// 通用适配器：把 [LegacyAgentRunner] 包成 [SpecialistAgent]。
///
/// 承担每个现有 agent 都要的通用逻辑：流式 chunk → 汇总为 [AgentResult]；工具调用 → [AgentProgress]；
/// 错误 → [AgentError]；确认 → [AgentNeedConfirm]。
class SpecialistAdapter extends SpecialistAgent {
  @override
  final AgentCapability capability;
  final LegacyAgentRunner runner;

  SpecialistAdapter(this.capability, this.runner);

  @override
  Stream<AgentEvent> handle(TaskEnvelope task) async* {
    final buf = StringBuffer();
    await for (final e in runner.run(task.text, context: task.context, userId: task.userId)) {
      switch (e.signal) {
        case RunnerSignal.firstToken:
        case RunnerSignal.toolCallResult:
          break;
        case RunnerSignal.chunk:
          if (e.text != null) {
            buf.write(e.text);
            yield AgentPartial(e.text!);
          }
        case RunnerSignal.toolCallStart:
          yield AgentProgress('调用工具：${e.toolName ?? ''}');
        case RunnerSignal.needConfirm:
          if (e.confirm != null) yield AgentNeedConfirm(e.confirm!);
        case RunnerSignal.done:
          final text = (e.text != null && e.text!.isNotEmpty) ? e.text! : buf.toString();
          yield AgentResult(text: text);
        case RunnerSignal.error:
          yield AgentError(e.errorCode ?? 'error', e.errorMessage ?? '未知错误');
      }
    }
  }
}
