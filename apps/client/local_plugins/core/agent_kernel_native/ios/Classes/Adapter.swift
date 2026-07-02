import Foundation

// 把"现有 agent"包成 SpecialistAgent，不改其基础模板。镜像 Dart/Kotlin 适配器。

enum RunnerSignal { case firstToken, chunk, toolCallStart, toolCallResult, done, error, needConfirm }

struct RunnerEvent {
    let signal: RunnerSignal
    let text: String?
    let toolName: String?
    let errorCode: String?
    let errorMessage: String?
    let confirm: Confirm?
    init(_ signal: RunnerSignal, text: String? = nil, toolName: String? = nil,
         errorCode: String? = nil, errorMessage: String? = nil, confirm: Confirm? = nil) {
        self.signal = signal; self.text = text; self.toolName = toolName
        self.errorCode = errorCode; self.errorMessage = errorMessage; self.confirm = confirm
    }
    static func chunk(_ t: String) -> RunnerEvent { RunnerEvent(.chunk, text: t) }
    static func done(_ t: String? = nil) -> RunnerEvent { RunnerEvent(.done, text: t) }
    static func error(_ code: String, _ msg: String) -> RunnerEvent { RunnerEvent(.error, errorCode: code, errorMessage: msg) }
    static func tool(_ name: String) -> RunnerEvent { RunnerEvent(.toolCallStart, toolName: name) }
    static func confirmNeeded(_ c: Confirm) -> RunnerEvent { RunnerEvent(.needConfirm, confirm: c) }
}

/// 由 app 用现有 agent 既有接口实现（startSession/sendText + onLlmChunk/onLlmDone… → RunnerEvent）。
protocol LegacyAgentRunner {
    func run(_ text: String, context: String?, userId: String?) -> [RunnerEvent]
}

final class SpecialistAdapter: SpecialistAgent {
    let capability: AgentCapability
    private let runner: LegacyAgentRunner
    init(_ capability: AgentCapability, _ runner: LegacyAgentRunner) {
        self.capability = capability; self.runner = runner
    }
    func handle(_ task: TaskEnvelope) -> [AgentEvent] {
        var out: [AgentEvent] = []
        var buf = ""
        for e in runner.run(task.text, context: task.context, userId: task.userId) {
            switch e.signal {
            case .firstToken, .toolCallResult:
                break
            case .chunk:
                if let t = e.text { buf += t; out.append(.partial(t)) }
            case .toolCallStart:
                out.append(.progress("调用工具：\(e.toolName ?? "")"))
            case .needConfirm:
                if let c = e.confirm { out.append(.needConfirm(c)) }
            case .done:
                out.append(.result((e.text?.isEmpty == false) ? e.text! : buf))
            case .error:
                out.append(.error(code: e.errorCode ?? "error", message: e.errorMessage ?? "未知错误"))
            }
        }
        return out
    }
}
