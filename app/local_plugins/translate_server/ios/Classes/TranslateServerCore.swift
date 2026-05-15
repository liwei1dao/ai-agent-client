import Flutter
import Foundation

/// 复合翻译场景的总编排器（iOS 进程内单例）—— 与 Android `TranslateServerCore` 对齐。
final class TranslateServerCore {

    static let shared = TranslateServerCore()
    private init() {}

    private let lock = NSLock()
    private var active: CallTranslationSession?
    private var emit: (([String: Any?]) -> Void)?

    private var deviceMethod: FlutterMethodChannel?

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

    func startCallTranslation(sessionId: String, request: CallTranslationRequest) throws -> String {
        lock.lock()
        if let a = active {
            lock.unlock()
            throw NSError(
                domain: "translate_server", code: -1,
                userInfo: [NSLocalizedDescriptionKey:
                    "translate.session_busy: another session \(a.sessionId) is active"]
            )
        }
        guard let emitter = emit, let dm = deviceMethod else {
            lock.unlock()
            throw NSError(
                domain: "translate_server", code: -2,
                userInfo: [NSLocalizedDescriptionKey: "translate.not_bound: emit/messenger missing"]
            )
        }
        let session = CallTranslationSession(
            sessionId: sessionId,
            request: request,
            deviceMethod: dm,
            emit: emitter
        )
        active = session
        lock.unlock()

        emitter(TranslateEvents.sessionState(sessionId: sessionId, state: "starting"))
        session.start()
        return sessionId
    }

    func stopActive() {
        lock.lock()
        let target = active
        active = nil
        lock.unlock()
        target?.stop()
    }
}
