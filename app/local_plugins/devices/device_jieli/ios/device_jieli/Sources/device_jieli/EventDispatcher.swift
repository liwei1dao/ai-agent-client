import Flutter
import Foundation

/// 与 Android 端 `EventDispatcher` 同语义：
///   - 内部维护一个 `FlutterEventSink` 与一组 native 监听器
///   - `send(_:)` 一次同时分发给两边
///   - Flutter 端事件强制在 main thread 投递
public final class EventDispatcher: NSObject, FlutterStreamHandler {

    public typealias NativeListener = (_ payload: [String: Any?]) -> Void

    private let lock = NSLock()
    private var sink: FlutterEventSink?
    private var nativeListeners: [(UUID, NativeListener)] = []

    public override init() { super.init() }

    // MARK: - FlutterStreamHandler

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        lock.lock(); defer { lock.unlock() }
        sink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        lock.lock(); defer { lock.unlock() }
        sink = nil
        return nil
    }

    // MARK: - Native subscription

    @discardableResult
    public func addNativeListener(_ listener: @escaping NativeListener) -> UUID {
        let id = UUID()
        lock.lock()
        nativeListeners.append((id, listener))
        lock.unlock()
        return id
    }

    public func removeNativeListener(_ id: UUID) {
        lock.lock()
        nativeListeners.removeAll { $0.0 == id }
        lock.unlock()
    }

    // MARK: - Send

    /// 直接外抛事件。同时通知 native 监听器和 Flutter sink。
    /// payload 必须是 plugin-channel 可序列化的形态（基本类型 / Map / List / FlutterStandardTypedData）。
    public func send(_ payload: [String: Any?]) {
        // native 监听同步派发（在调用方线程，避免高频音频帧切换 thread 的额外开销）
        let listeners: [NativeListener]
        let sinkCopy: FlutterEventSink?
        lock.lock()
        listeners = nativeListeners.map { $0.1 }
        sinkCopy = sink
        lock.unlock()

        for l in listeners { l(payload) }

        guard let s = sinkCopy else { return }
        let cleaned = payload.reduce(into: [String: Any]()) { acc, kv in
            if let v = kv.value { acc[kv.key] = v }
        }
        if Thread.isMainThread {
            s(cleaned)
        } else {
            DispatchQueue.main.async { s(cleaned) }
        }
    }
}
