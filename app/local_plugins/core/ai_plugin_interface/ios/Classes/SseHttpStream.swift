import Foundation

/// URLSession-backed Server-Sent-Events reader.
///
/// Exposes incoming bytes line-by-line as an `AsyncThrowingStream`. Used by
/// LLM service implementations (`LlmOpenaiService`, `LlmVolcengineService`)
/// to consume `data: …` frames at their own pace and to cancel the request
/// when a newer turn arrives.
///
/// Workflow:
///   1. `init(session:request:)`
///   2. `try await start()` — sends the request, awaits response headers.
///   3. `for try await line in stream.lines()` — pull body lines.
///   4. `stream.cancel()` to abort at any moment.
public final class SseHttpStream: NSObject, URLSessionDataDelegate {
    public private(set) var task: URLSessionDataTask?

    private let request: URLRequest
    private let configuration: URLSessionConfiguration
    private let queueLock = NSLock()

    public private(set) var response: URLResponse?
    private var responseContinuation: CheckedContinuation<Void, Error>?

    private var buffer = Data()
    private var lineContinuation: AsyncThrowingStream<String, Error>.Continuation?

    private var bodyTail = Data()
    private var streamFinished = false
    private var bodyDrainContinuation: CheckedContinuation<String, Never>?

    private var delegateSession: URLSession?

    public init(session sourceSession: URLSession, request: URLRequest) {
        self.request = request
        self.configuration = sourceSession.configuration
        super.init()
    }

    deinit {
        delegateSession?.invalidateAndCancel()
    }

    /// Send the request and wait for response headers.
    public func start() async throws {
        let s = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        delegateSession = s
        let dataTask = s.dataTask(with: request)
        queueLock.lock(); task = dataTask; queueLock.unlock()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queueLock.lock(); responseContinuation = cont; queueLock.unlock()
            dataTask.resume()
        }
    }

    /// Line-by-line async stream of the response body (no trailing newline).
    public func lines() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            self.queueLock.lock()
            self.lineContinuation = continuation
            self.queueLock.unlock()
            continuation.onTermination = { @Sendable [weak self] _ in
                self?.cancel()
            }
        }
    }

    public func cancel() {
        queueLock.lock()
        let t = task
        task = nil
        let lc = lineContinuation
        lineContinuation = nil
        queueLock.unlock()
        t?.cancel()
        lc?.finish()
    }

    /// Best-effort error-body preview (used when the request is non-2xx).
    public func drainBodyPreview(limit: Int) async -> String {
        await withCheckedContinuation { cont in
            queueLock.lock()
            if streamFinished {
                let data = bodyTail.prefix(limit)
                queueLock.unlock()
                cont.resume(returning: String(data: Data(data), encoding: .utf8) ?? "")
                return
            }
            bodyDrainContinuation = cont
            queueLock.unlock()
        }
    }

    // ── URLSessionDataDelegate ────────────────────────────────────

    public func urlSession(_ session: URLSession,
                           dataTask: URLSessionDataTask,
                           didReceive response: URLResponse,
                           completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        queueLock.lock()
        self.response = response
        let cont = responseContinuation
        responseContinuation = nil
        queueLock.unlock()
        cont?.resume()
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession,
                           dataTask: URLSessionDataTask,
                           didReceive data: Data) {
        queueLock.lock()
        bodyTail.append(data.prefix(2048))
        let cont = lineContinuation
        if cont != nil {
            buffer.append(data)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer.subdata(in: 0..<nl)
                buffer.removeSubrange(0...nl)
                if let line = String(data: lineData, encoding: .utf8) {
                    let stripped = line.hasSuffix("\r") ? String(line.dropLast()) : line
                    queueLock.unlock()
                    cont?.yield(stripped)
                    queueLock.lock()
                }
            }
        }
        queueLock.unlock()
    }

    public func urlSession(_ session: URLSession,
                           task: URLSessionTask,
                           didCompleteWithError error: Error?) {
        queueLock.lock()
        streamFinished = true
        let pendingDrain = bodyDrainContinuation
        bodyDrainContinuation = nil
        let tail = bodyTail
        let respCont = responseContinuation
        responseContinuation = nil
        let lineCont = lineContinuation
        lineContinuation = nil
        let leftover = buffer
        buffer.removeAll()
        queueLock.unlock()

        pendingDrain?.resume(returning: String(data: tail, encoding: .utf8) ?? "")

        if let error = error {
            respCont?.resume(throwing: error)
            lineCont?.finish(throwing: error)
        } else {
            respCont?.resume()
            if !leftover.isEmpty, let line = String(data: leftover, encoding: .utf8) {
                lineCont?.yield(line)
            }
            lineCont?.finish()
        }
    }
}
