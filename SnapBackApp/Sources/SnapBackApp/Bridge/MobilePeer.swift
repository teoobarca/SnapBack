import Foundation
import Network

public final class MobilePeer {
    public enum State: Equatable { case idle, connecting, connected, disconnected }

    public var onStateChange: ((State) -> Void)?
    public var onMessage: ((ProtocolMessage) -> Void)?

    public let host: String
    public let port: UInt16
    private let secret: Data
    private let peerName: String
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.snapback.bridge.mobilePeer")
    private var state: State = .idle { didSet { onStateChange?(state) } }
    private var reconnectAttempt = 0
    private var buffer = Data()
    private var stopRequested = false
    private var helloTimeout: DispatchWorkItem?
    // Replay protection on the receive path. Sized for a long session at
    // ~30 s heartbeat cadence; 1024 is vastly more than any real phone ever
    // produces in the 10 min TTL window.
    private let nonceCache = NonceCache(capacity: 1024, ttlSeconds: 600)

    public init(host: String, port: UInt16, secret: Data, peerName: String) {
        self.host = host
        self.port = port
        self.secret = secret
        self.peerName = peerName
    }

    public func start() {
        queue.async { self.connect() }
    }

    public func stop() {
        queue.async {
            self.stopRequested = true
            self.helloTimeout?.cancel()
            self.helloTimeout = nil
            self.state = .disconnected
            self.connection?.cancel()
            self.connection = nil
        }
    }

    /// Send a signed message to the peer. This is only valid AFTER `onStateChange(.connected)`
    /// has fired — messages issued between `.ready` and the first verified inbound message
    /// (the `.connected` transition is driven by inbound traffic) are silently dropped.
    /// Phase 12's BridgeOrchestrator must gate sends on the `.connected` callback.
    public func send(_ message: ProtocolMessage) {
        queue.async {
            guard let conn = self.connection, self.state == .connected else { return }
            if let line = try? MessageCodec.encodeSignedLine(
                message, direction: .clientToServer, secret: self.secret) {
                conn.send(content: Data(line.utf8), completion: .idempotent)
            }
        }
    }

    private func connect() {
        guard !stopRequested else { return }
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            state = .disconnected
            return
        }
        state = .connecting
        let c = NWConnection(host: NWEndpoint.Host(host),
                             port: nwPort,
                             using: .tcp)
        connection = c
        c.stateUpdateHandler = { [weak self] s in
            guard let self else { return }
            switch s {
            case .ready:
                self.reconnectAttempt = 0
                self.sendHello()
                self.receiveLoop()
                self.armHelloTimeout()
            case .failed:
                self.state = .disconnected
                self.scheduleReconnect()
            case .cancelled:
                // Only reconnect if this cancel was not triggered by stop().
                guard !self.stopRequested else { return }
                self.state = .disconnected
                self.scheduleReconnect()
            case .waiting:
                // NWConnection stays in .waiting when server is unreachable.
                // Cancel and reschedule so we get a fresh connection attempt
                // when the server comes back (avoids the NW waiting-state latch).
                self.connection?.cancel()
            default:
                break
            }
        }
        c.start(queue: queue)
    }

    private func scheduleReconnect() {
        guard !stopRequested else { return }
        let attempt = reconnectAttempt
        reconnectAttempt += 1
        let delays: [TimeInterval] = [0.5, 2.0, 8.0, 30.0]
        let d = attempt < delays.count ? delays[attempt] : 120.0
        queue.asyncAfter(deadline: .now() + d) { [weak self] in
            guard let self else { return }
            guard !self.stopRequested else { return }
            guard self.state == .disconnected else { return }
            self.connect()
        }
    }

    private func armHelloTimeout() {
        helloTimeout?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.state == .connecting else { return }
            self.connection?.cancel()
        }
        helloTimeout = item
        queue.asyncAfter(deadline: .now() + 5.0, execute: item)
    }

    private func sendHello() {
        let nonce = (0..<16).map { _ in UInt8.random(in: 0...255) }
                             .map { String(format: "%02x", $0) }.joined()
        let msg = ProtocolMessage(
            version: 1, type: .hello,
            timestamp: Int64(Date().timeIntervalSince1970),
            nonceHex: nonce,
            payload: [("app_version", .string("1.3.0")),
                      ("peer_name", .string(peerName))]
        )
        if let line = try? MessageCodec.encodeSignedLine(msg, direction: .clientToServer, secret: secret) {
            connection?.send(content: Data(line.utf8), completion: .idempotent)
        }
    }

    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
            [weak self] data, _, isComplete, _ in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                while let nl = self.buffer.firstIndex(of: 0x0A) {
                    let line = String(data: self.buffer[..<nl], encoding: .utf8) ?? ""
                    self.buffer.removeSubrange(...nl)
                    self.dispatch(line: line)
                }
            }
            if isComplete {
                self.state = .disconnected
                self.connection?.cancel()
                return
            }
            self.receiveLoop()
        }
    }

    private func dispatch(line: String) {
        guard let (msg, hmac) = try? MessageCodec.decodeLine(line + "\n") else { return }
        guard MessageCodec.verify(message: msg, direction: .serverToClient,
                                  hmacHex: hmac, secret: secret) else { return }
        // Replay protection: reject any nonce we've already accepted within TTL.
        // Clock drift beyond the codec's ±30 s window was already rejected above.
        let now = Date().timeIntervalSince1970
        guard nonceCache.tryAdd(msg.nonceHex, at: now) else { return }
        if state != .connected {
            state = .connected
            helloTimeout?.cancel()
            helloTimeout = nil
        }
        onMessage?(msg)
    }
}
