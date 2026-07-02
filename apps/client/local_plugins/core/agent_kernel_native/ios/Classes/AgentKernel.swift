import Foundation

// 多 Agent 团队编排内核（Swift）——镜像已跑绿的 Dart core/agent_kernel。
// 供纯原生 agents_server 直接使用。骨架用同步 [AgentEvent]（流式后续可换回调/Combine）。

typealias AgentId = String

enum AgentStatus { case ok, partial, rejected, failed }

struct AgentCapability {
    let id: AgentId
    let name: String
    let keywords: [String]
    let description: String
    let triggers: [String]
    init(id: AgentId, name: String, keywords: [String] = [], description: String = "", triggers: [String] = []) {
        self.id = id; self.name = name; self.keywords = keywords; self.description = description; self.triggers = triggers
    }
}

struct TaskEnvelope {
    let taskId: String
    let requestId: String
    let from: AgentId
    let to: AgentId
    let intent: String
    let text: String
    let params: [String: Any]
    let context: String?
    let userId: String?
    let needConfirm: Bool
    init(taskId: String, requestId: String, from: AgentId, to: AgentId, intent: String, text: String,
         params: [String: Any] = [:], context: String? = nil, userId: String? = nil, needConfirm: Bool = false) {
        self.taskId = taskId; self.requestId = requestId; self.from = from; self.to = to
        self.intent = intent; self.text = text; self.params = params
        self.context = context; self.userId = userId; self.needConfirm = needConfirm
    }
}

struct Citation {
    let title: String
    let ref: String?
    init(_ title: String, ref: String? = nil) { self.title = title; self.ref = ref }
}

struct Confirm {
    let id: String
    let actionKind: String
    let summary: String
    let preview: [String: Any]
    let editable: Bool
    init(id: String, actionKind: String, summary: String, preview: [String: Any] = [:], editable: Bool = true) {
        self.id = id; self.actionKind = actionKind; self.summary = summary; self.preview = preview; self.editable = editable
    }
}

enum AgentEvent {
    case partial(String)
    case progress(String)
    case result(text: String, status: AgentStatus, citations: [Citation])
    case needConfirm(Confirm)
    case error(code: String, message: String)

    /// 便捷构造（默认 status=.ok）。
    static func result(_ text: String, citations: [Citation] = []) -> AgentEvent {
        .result(text: text, status: .ok, citations: citations)
    }
}

struct ManagerReply {
    let text: String
    let usedAgents: [AgentId]
    let citations: [Citation]
    let pendingConfirm: Confirm?
    var needsConfirm: Bool { pendingConfirm != nil }
}

enum WakeSource { case device, hotword, schedule, incomingCall, geofence, push }
struct WakeEvent {
    let source: WakeSource
    let sourceId: String
    let utterance: String?
    let payload: [String: Any]
    init(source: WakeSource, sourceId: String, utterance: String? = nil, payload: [String: Any] = [:]) {
        self.source = source; self.sourceId = sourceId; self.utterance = utterance; self.payload = payload
    }
}
struct TriggerContext {
    let kind: String
    let source: String
    let params: [String: Any]
    init(kind: String, source: String, params: [String: Any] = [:]) {
        self.kind = kind; self.source = source; self.params = params
    }
}

protocol SpecialistAgent {
    var capability: AgentCapability { get }
    func handle(_ task: TaskEnvelope) -> [AgentEvent]
    func onTrigger(_ ctx: TriggerContext) -> [AgentEvent]
}
extension SpecialistAgent {
    func onTrigger(_ ctx: TriggerContext) -> [AgentEvent] { [] }
}

protocol ContextProvider { func contextFor(_ query: String, userId: String?) -> String? }
protocol Router { func route(_ text: String, caps: [AgentCapability], userId: String?) -> [AgentId] }
protocol LlmRouter { func pick(_ text: String, caps: [AgentCapability]) -> AgentId? }

final class RuleRouter: Router {
    private let fallback: AgentId
    private let llm: LlmRouter?
    init(fallback: AgentId = "chat", llm: LlmRouter? = nil) { self.fallback = fallback; self.llm = llm }
    func route(_ text: String, caps: [AgentCapability], userId: String?) -> [AgentId] {
        let lower = text.lowercased()
        let matched = caps.filter { c in c.keywords.contains { lower.contains($0.lowercased()) } }.map { $0.id }
        if !matched.isEmpty { return matched }
        if let p = llm?.pick(text, caps: caps) { return [p] }
        return [fallback]
    }
}

/// 管家：单一发声——路由 → 分派 → 汇总 + 上下文注入 + 确认闸口 + 唤醒。
final class Manager {
    private let router: Router
    private let contextProvider: ContextProvider?
    private var agents: [AgentId: SpecialistAgent] = [:]
    private var order: [AgentId] = []
    private var seq = 0

    init(router: Router, contextProvider: ContextProvider? = nil) {
        self.router = router; self.contextProvider = contextProvider
    }

    private func nextId(_ p: String) -> String { defer { seq += 1 }; return "\(p)-\(seq)" }

    func register(_ a: SpecialistAgent) {
        if agents[a.capability.id] == nil { order.append(a.capability.id) }
        agents[a.capability.id] = a
    }

    var capabilities: [AgentCapability] { order.compactMap { agents[$0]?.capability } }

    func handle(_ userText: String, userId: String? = nil) -> ManagerReply {
        let requestId = nextId("req")
        let context = contextProvider?.contextFor(userText, userId: userId)
        let ids = router.route(userText, caps: capabilities, userId: userId)
        var used: [AgentId] = []
        var citations: [Citation] = []
        var buf = ""
        var pending: Confirm?
        for aid in ids {
            guard let agent = agents[aid] else { continue }
            used.append(aid)
            let task = TaskEnvelope(taskId: nextId("task"), requestId: requestId, from: "manager",
                                    to: aid, intent: agent.capability.id, text: userText,
                                    context: context, userId: userId)
            for e in agent.handle(task) {
                switch e {
                case .result(let text, _, let cits):
                    if !buf.isEmpty { buf += "\n" }; buf += text; citations += cits
                case .needConfirm(let c):
                    pending = c
                case .error(_, let message):
                    if !buf.isEmpty { buf += "\n" }; buf += "（\(aid) 出错：\(message)）"
                case .partial, .progress:
                    break
                }
            }
        }
        return ManagerReply(text: buf, usedAgents: used, citations: citations, pendingConfirm: pending)
    }

    /// 服务级唤醒入口（被 WakeBus 调起，可能无 Flutter 在场）。
    func onWake(_ e: WakeEvent) -> ManagerReply? {
        guard let text = e.utterance, !text.isEmpty else { return nil }
        return handle(text, userId: e.payload["userId"] as? String)
    }
}

/// 框架层唤醒总线。
final class WakeBus {
    private var handlers: [(WakeEvent) -> Void] = []
    func on(_ h: @escaping (WakeEvent) -> Void) { handlers.append(h) }
    func emit(_ e: WakeEvent) { for h in handlers { h(e) } }
}
