import Flutter
import Foundation

/// AI 助理场景的总编排器（iOS 进程内单例）—— 与 Android `AssistantServerCore` 对齐。
///
/// 互斥：[active] 至多一个会话；新 start 调用时若已有 active 则抛 `assistant.session_busy`。
final class AssistantServerCore {

    static let shared = AssistantServerCore()
    private init() {}

    private let lock = NSLock()
    private var active: AssistantSession?
    private var emit: (([String: Any?]) -> Void)?

    private var deviceMethod: FlutterMethodChannel?

    /// 由 Plugin 在 onAttached 时注入；EventChannel 转发器 + device_jieli MethodChannel。
    func bindContext(messenger: FlutterBinaryMessenger,
                     emitter: @escaping ([String: Any?]) -> Void) {
        lock.lock()
        self.emit = emitter
        if self.deviceMethod == nil {
            self.deviceMethod = FlutterMethodChannel(
                name: "device_jieli/method",
                binaryMessenger: messenger
            )
        }
        lock.unlock()
    }

    func unbindEmitter() {
        lock.lock(); emit = nil; lock.unlock()
    }

    func activeSessionId() -> String? {
        lock.lock(); defer { lock.unlock() }
        return active?.sessionId
    }

    /// 启动 AI 助理会话。返回 sessionId。
    func startAssistant(sessionId: String, request: AssistantRequest) throws -> String {
        lock.lock()
        if let a = active {
            lock.unlock()
            throw NSError(
                domain: "assistant_server", code: -1,
                userInfo: [NSLocalizedDescriptionKey:
                    "assistant.session_busy: another session \(a.sessionId) is active"]
            )
        }
        guard let emitter = emit, let dm = deviceMethod else {
            lock.unlock()
            throw NSError(
                domain: "assistant_server", code: -2,
                userInfo: [NSLocalizedDescriptionKey: "assistant.not_bound: emit/messenger missing"]
            )
        }
        let session = AssistantSession(
            sessionId: sessionId,
            request: request,
            deviceMethod: dm,
            emit: emitter
        )
        active = session
        lock.unlock()

        emitter(AssistantEvents.sessionState(sessionId: sessionId, state: "starting"))
        session.start()

        // 监听 stopped 时把 active 清空 —— 通过观察 sessionState 事件
        // 实际是 AssistantSession.stop() 内部会 emit sessionState=stopped，
        // 这里不另做拦截；下一次 startAssistant 时如果 active 不是 stopped 的，
        // 会按 session_busy 拒绝。简单起见，给 stop 路径加 clearIfMatches。
        return sessionId
    }

    /// 停止当前 active session。无 active 时 no-op。
    func stopActive() {
        lock.lock()
        let target = active
        active = nil
        lock.unlock()
        target?.stop()
    }
}
