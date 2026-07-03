import Foundation
import WebRTC
import os.log

/// VoiTrans (PolyChat) WebRTC session shared by `sts_polychat` and
/// `ast_polychat`.
///
/// Ports the Kotlin `VoitransWebRtcSession`. Handshake:
///   1. `POST {baseUrl}/open/v1/agents/{agentId}/connect`
///      headers: `X-App-Id` / `X-App-Secret` → `{connect_url, token}`
///   2. Create `RTCPeerConnection` + local audio track + DataChannel,
///      generate SDP offer.
///   3. `POST {connect_url}` with `{sdp, type, request_data: {connect_token,
///      agent_id}}` → `{pc_id, sdp}` answer.
///   4. PATCH `{baseUrl}/api/offer` with `{pc_id, candidates}` once
///      remoteDescription is set.
///   5. DataChannel ping heartbeat every 1s (text "ping") — the server
///      drops the session if no ping is seen in a ~3s window.
///   6. On release, `DELETE {baseUrl}/api/sessions/{pc_id}` to clean up.
public final class VoitransWebRtcSession: NSObject {

    public struct EventHandler {
        public var onConnected: () -> Void
        public var onMessage: ([String: Any]) -> Void
        public var onDisconnected: () -> Void
        public var onError: (_ code: String, _ message: String) -> Void

        public init(
            onConnected: @escaping () -> Void,
            onMessage: @escaping ([String: Any]) -> Void,
            onDisconnected: @escaping () -> Void,
            onError: @escaping (_ code: String, _ message: String) -> Void
        ) {
            self.onConnected = onConnected
            self.onMessage = onMessage
            self.onDisconnected = onDisconnected
            self.onError = onError
        }
    }

    private static let log = OSLog(subsystem: "com.aiagent.plugin_interface", category: "VoitransWebRtc")

    // ── Shared factory ─────────────────────────────────────────────

    private static let factoryLock = NSLock()
    private static var sharedFactory: RTCPeerConnectionFactory?
    private static let httpSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 10
        cfg.timeoutIntervalForResource = 30
        return URLSession(configuration: cfg)
    }()

    /// Pre-warm the WebRTC factory (call from `FlutterPlugin.register`
    /// to avoid a first-connection stall).
    public static func warmup() {
        _ = factory()
    }

    /// DNS + TLS pre-warm against the signaling host. Optional.
    public static func warmupHttp(baseUrl: String) {
        guard let url = URL(string: baseUrl.trimmingTrailingSlash() + "/open/v1/agents") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        httpSession.dataTask(with: req) { _, _, _ in }.resume()
    }

    private static func factory() -> RTCPeerConnectionFactory {
        factoryLock.lock(); defer { factoryLock.unlock() }
        if let f = sharedFactory { return f }
        RTCInitializeSSL()
        let videoEncoder = RTCDefaultVideoEncoderFactory()
        let videoDecoder = RTCDefaultVideoDecoderFactory()
        let f = RTCPeerConnectionFactory(
            encoderFactory: videoEncoder,
            decoderFactory: videoDecoder
        )
        sharedFactory = f
        return f
    }

    // ── Configuration ──────────────────────────────────────────────

    private var baseUrl: String = ""
    private var appId: String = ""
    private var appSecret: String = ""
    private var agentId: String = ""

    // ── State ──────────────────────────────────────────────────────

    private var handler: EventHandler?
    private var peer: RTCPeerConnection?
    private var localAudioTrack: RTCAudioTrack?
    private var dataChannel: RTCDataChannel?
    private var pcId: String?
    private var pendingCandidates: [RTCIceCandidate] = []
    private var remoteDescriptionSet = false
    private let stateLock = NSLock()
    private var pingTimer: DispatchSourceTimer?
    private var released = false

    public override init() {
        super.init()
    }

    deinit {
        release()
    }

    // ── Public API ─────────────────────────────────────────────────

    public func initialize(baseUrl: String, appId: String, appSecret: String, agentId: String) {
        self.baseUrl = baseUrl.trimmingTrailingSlash()
        self.appId = appId
        self.appSecret = appSecret
        self.agentId = agentId
    }

    /// Start the connect handshake. Reports back via `handler` callbacks.
    public func connect(handler: EventHandler) {
        self.handler = handler
        Task.detached { [weak self] in
            await self?.runConnect()
        }
    }

    public func startAudio() {
        localAudioTrack?.isEnabled = true
    }

    public func stopAudio() {
        localAudioTrack?.isEnabled = false
    }

    /// Send a JSON control message via the DataChannel.
    public func sendDataChannelMessage(_ json: [String: Any]) {
        guard let dc = dataChannel, dc.readyState == .open else {
            os_log("DataChannel not open — drop %{public}@",
                   log: Self.log, type: .info, String(describing: json))
            return
        }
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return }
        let buffer = RTCDataBuffer(data: data, isBinary: false)
        dc.sendData(buffer)
    }

    public func release() {
        stateLock.lock()
        if released {
            stateLock.unlock()
            return
        }
        released = true
        let id = pcId
        pcId = nil
        let h = handler
        handler = nil
        stateLock.unlock()

        if let id = id {
            // Best-effort session deletion. Path segment is URL-encoded
            // because `pc_id` may contain `#`.
            if let encoded = id.addingPercentEncoding(
                withAllowedCharacters: CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "#"))
            ),
               let url = URL(string: "\(baseUrl)/api/sessions/\(encoded)") {
                var req = URLRequest(url: url)
                req.httpMethod = "DELETE"
                Self.httpSession.dataTask(with: req).resume()
            }
        }

        stopPingHeartbeat()
        dataChannel?.close()
        dataChannel = nil
        peer?.close()
        peer = nil
        localAudioTrack = nil
        h?.onDisconnected()
    }

    // ── Handshake ──────────────────────────────────────────────────

    private func runConnect() async {
        do {
            let tokenResponse = try await requestConnectToken()
            let rawConnectUrl = (tokenResponse["connect_url"] as? String) ?? ""
            let connectUrl = rawConnectUrl.hasPrefix("http://")
                ? "https://" + rawConnectUrl.dropFirst("http://".count)
                : rawConnectUrl
            let token = (tokenResponse["token"] as? String) ?? ""

            try createPeer()
            createLocalAudioTrack()
            let offerSdp = try await createOfferSdp()

            let answer = try await sendOffer(connectUrl: connectUrl, sdp: offerSdp, token: token)
            let pcIdVal = (answer["pc_id"] as? String) ?? ""
            let answerSdp = (answer["sdp"] as? String) ?? ""

            stateLock.lock(); pcId = pcIdVal; stateLock.unlock()

            try await setRemoteDescription(sdp: answerSdp)
            stateLock.lock(); remoteDescriptionSet = true; stateLock.unlock()
            flushPendingCandidates()
        } catch {
            os_log("connect failed: %{public}@", log: Self.log, type: .error,
                   error.localizedDescription)
            handler?.onError("connect_failed", error.localizedDescription)
        }
    }

    // ── HTTP: connect token ────────────────────────────────────────

    private func requestConnectToken() async throws -> [String: Any] {
        guard let url = URL(string: "\(baseUrl)/open/v1/agents/\(agentId)/connect") else {
            throw NSError(domain: "voitrans", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "invalid baseUrl"])
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(appId, forHTTPHeaderField: "X-App-Id")
        req.setValue(appSecret, forHTTPHeaderField: "X-App-Secret")
        req.httpBody = Data("{}".utf8)
        let (data, resp) = try await Self.httpSession.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "voitrans", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey:
                            "Connect token request failed: \(http.statusCode) \(body)"])
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "voitrans", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "invalid token response"])
        }
        return json
    }

    // ── HTTP: offer / answer ───────────────────────────────────────

    private func sendOffer(connectUrl: String, sdp: String, token: String) async throws -> [String: Any] {
        guard let url = URL(string: connectUrl) else {
            throw NSError(domain: "voitrans", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "invalid connect_url: \(connectUrl)"])
        }
        let body: [String: Any] = [
            "sdp": sdp,
            "type": "offer",
            "request_data": [
                "connect_token": token,
                "agent_id": agentId,
            ],
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await Self.httpSession.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "voitrans", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey:
                            "Offer request failed: \(http.statusCode) \(bodyStr)"])
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "voitrans", code: -4,
                          userInfo: [NSLocalizedDescriptionKey: "invalid offer response"])
        }
        return json
    }

    private func sendIceCandidates(_ candidates: [RTCIceCandidate]) async {
        guard let id = pcId else { return }
        let arr: [[String: Any]] = candidates.map { c in
            [
                "candidate": c.sdp,
                "sdp_mid": c.sdpMid ?? "",
                "sdp_mline_index": c.sdpMLineIndex,
            ]
        }
        let body: [String: Any] = ["pc_id": id, "candidates": arr]
        guard let url = URL(string: "\(baseUrl)/api/offer"),
              let payload = try? JSONSerialization.data(withJSONObject: body) else {
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = payload
        _ = try? await Self.httpSession.data(for: req)
    }

    // ── PeerConnection ─────────────────────────────────────────────

    private func createPeer() throws {
        let config = RTCConfiguration()
        config.iceServers = [
            RTCIceServer(urlStrings: ["stun:stun.miwifi.com:3478"]),
            RTCIceServer(urlStrings: ["stun:stun.chat.bilibili.com:3478"]),
            RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"]),
        ]
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually
        // MAX_BUNDLE so audio + DataChannel share a single ICE/DTLS transport.
        // Otherwise trickle-ICE only feeds one m-line and the SCTP DataChannel
        // never opens.
        config.bundlePolicy = .maxBundle
        config.rtcpMuxPolicy = .require

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: nil
        )
        guard let pc = Self.factory().peerConnection(
            with: config,
            constraints: constraints,
            delegate: self
        ) else {
            throw NSError(domain: "voitrans", code: -5,
                          userInfo: [NSLocalizedDescriptionKey: "createPeerConnection failed"])
        }
        peer = pc

        let dcConfig = RTCDataChannelConfiguration()
        dcConfig.isOrdered = true
        if let dc = pc.dataChannel(forLabel: "events", configuration: dcConfig) {
            attachDataChannel(dc)
        }
    }

    private func createLocalAudioTrack() {
        guard let pc = peer else { return }
        let factory = Self.factory()
        let audioSource = factory.audioSource(with: RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: nil
        ))
        let track = factory.audioTrack(with: audioSource, trackId: "audio_local")
        // Parity with the Web client: leave the track enabled during
        // negotiation; callers toggle via `startAudio()` / `stopAudio()`.
        track.isEnabled = true
        pc.add(track, streamIds: ["local_stream"])
        localAudioTrack = track
    }

    private func createOfferSdp() async throws -> String {
        guard let pc = peer else {
            throw NSError(domain: "voitrans", code: -6,
                          userInfo: [NSLocalizedDescriptionKey: "no peer connection"])
        }
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true",
                "OfferToReceiveVideo": "false",
            ],
            optionalConstraints: nil
        )
        let offer: RTCSessionDescription = try await withCheckedThrowingContinuation { cont in
            pc.offer(for: constraints) { sdp, err in
                if let err = err {
                    cont.resume(throwing: err)
                } else if let sdp = sdp {
                    cont.resume(returning: sdp)
                } else {
                    cont.resume(throwing: NSError(domain: "voitrans", code: -7,
                                                  userInfo: [NSLocalizedDescriptionKey: "no sdp"]))
                }
            }
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            pc.setLocalDescription(offer) { err in
                if let err = err { cont.resume(throwing: err) }
                else { cont.resume() }
            }
        }
        return offer.sdp
    }

    private func setRemoteDescription(sdp: String) async throws {
        guard let pc = peer else { return }
        let answer = RTCSessionDescription(type: .answer, sdp: sdp)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            pc.setRemoteDescription(answer) { err in
                if let err = err { cont.resume(throwing: err) }
                else { cont.resume() }
            }
        }
    }

    private func flushPendingCandidates() {
        stateLock.lock()
        let list = pendingCandidates
        pendingCandidates.removeAll()
        stateLock.unlock()
        guard !list.isEmpty else { return }
        Task.detached { [weak self] in
            await self?.sendIceCandidates(list)
        }
    }

    // ── DataChannel ────────────────────────────────────────────────

    private func attachDataChannel(_ dc: RTCDataChannel) {
        dataChannel = dc
        dc.delegate = self
    }

    private func startPingHeartbeat() {
        stopPingHeartbeat()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 1, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            guard let dc = self.dataChannel, dc.readyState == .open else { return }
            let buffer = RTCDataBuffer(data: Data("ping".utf8), isBinary: false)
            dc.sendData(buffer)
        }
        timer.resume()
        pingTimer = timer
    }

    private func stopPingHeartbeat() {
        pingTimer?.cancel()
        pingTimer = nil
    }
}

// MARK: - RTCPeerConnectionDelegate

extension VoitransWebRtcSession: RTCPeerConnectionDelegate {

    public func peerConnection(_ peerConnection: RTCPeerConnection,
                               didGenerate candidate: RTCIceCandidate) {
        stateLock.lock()
        let ready = remoteDescriptionSet
        if !ready {
            pendingCandidates.append(candidate)
            stateLock.unlock()
            return
        }
        stateLock.unlock()
        Task.detached { [weak self] in
            await self?.sendIceCandidates([candidate])
        }
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection,
                               didChange newState: RTCIceConnectionState) {
        os_log("ICE state: %d", log: Self.log, type: .debug, newState.rawValue)
        switch newState {
        case .connected:
            AudioOutputManager.shared.applyModeForWebRtc()
            handler?.onConnected()
        case .disconnected, .failed, .closed:
            handler?.onDisconnected()
        default:
            break
        }
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection,
                               didOpen dataChannel: RTCDataChannel) {
        os_log("Remote DataChannel: %{public}@",
               log: Self.log, type: .debug, dataChannel.label)
        attachDataChannel(dataChannel)
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection,
                               didChange stateChanged: RTCSignalingState) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection,
                               didAdd stream: RTCMediaStream) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection,
                               didRemove stream: RTCMediaStream) {}
    public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection,
                               didChange newState: RTCIceGatheringState) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection,
                               didRemove candidates: [RTCIceCandidate]) {}
}

// MARK: - RTCDataChannelDelegate

extension VoitransWebRtcSession: RTCDataChannelDelegate {
    public func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        os_log("DataChannel[%{public}@] state=%d",
               log: Self.log, type: .debug,
               dataChannel.label, dataChannel.readyState.rawValue)
        switch dataChannel.readyState {
        case .open:
            startPingHeartbeat()
        case .closed, .closing:
            stopPingHeartbeat()
        default:
            break
        }
    }

    public func dataChannel(_ dataChannel: RTCDataChannel,
                            didReceiveMessageWith buffer: RTCDataBuffer) {
        if buffer.isBinary { return }
        guard let str = String(data: buffer.data, encoding: .utf8) else { return }
        guard let parsed = try? JSONSerialization.jsonObject(with: Data(str.utf8))
                as? [String: Any] else {
            os_log("DataChannel: bad JSON %{public}@",
                   log: Self.log, type: .error, String(str.prefix(200)))
            return
        }
        handler?.onMessage(parsed)
    }
}

// MARK: - Helpers

private extension String {
    func trimmingTrailingSlash() -> String {
        var s = self
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
}
