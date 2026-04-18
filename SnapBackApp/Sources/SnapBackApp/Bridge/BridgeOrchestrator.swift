import Foundation

/// Wires the UDS-fed `EventQueue` to the phone-facing `MobilePeer`.
/// Owns HOLD-state lifecycle, heartbeat scheduling, and status publication.
///
/// Design notes:
///   • A 100 ms drain timer polls the event queue; a simpler and more reactive
///     implementation could enqueue-notify, but for 1.3.0 the polling loop is
///     adequate and keeps the queue API tiny.
///   • `MobilePeer.send` silently drops messages when `state != .connected`.
///     The orchestrator does NOT buffer events while disconnected — any
///     attention fired during a reconnect is lost. Acceptable for MVP: hooks
///     fire `attention` right before Claude blocks, so users are normally
///     nearby and the phone is reachable. A future improvement could hold
///     events and replay on `.connected`.
public final class BridgeOrchestrator {
    private let eventQueue: EventQueue
    private let peer: MobilePeer
    private let status: BridgeStatusPublisher
    private let heartbeat: HeartbeatLoop
    private let drainQueue = DispatchQueue(label: "com.snapback.bridge.orchestrator")
    private var drainTimer: DispatchSourceTimer?
    private var holdOutstanding = false

    public init(eventQueue: EventQueue,
                peer: MobilePeer,
                status: BridgeStatusPublisher,
                heartbeat: HeartbeatLoop = HeartbeatLoop(intervalSeconds: 30,
                                                        missesBeforeDead: 2)) {
        self.eventQueue = eventQueue
        self.peer = peer
        self.status = status
        self.heartbeat = heartbeat

        peer.onStateChange = { [weak self] s in
            guard let self else { return }
            switch s {
            case .connected:
                self.status.update(.connected)
                self.sendResync()
            case .connecting:
                self.status.update(.connecting)
            case .disconnected:
                self.status.update(.unreachable)
                self.heartbeat.stop()
            case .idle:
                self.status.update(.unpaired)
            }
        }
        peer.onMessage = { [weak self] msg in self?.handleInbound(msg) }

        heartbeat.onPing = { [weak self] in self?.sendHeartbeat() }
        heartbeat.onDeadPeer = { [weak self] in self?.holdOutstanding = false }
    }

    public func start() {
        peer.start()
        let t = DispatchSource.makeTimerSource(queue: drainQueue)
        t.schedule(deadline: .now() + 0.1, repeating: 0.1)
        t.setEventHandler { [weak self] in self?.drain() }
        t.resume()
        drainTimer = t
    }

    public func stop() {
        drainTimer?.cancel()
        drainTimer = nil
        heartbeat.stop()
        peer.stop()
    }

    // MARK: Private

    private func drain() {
        while let event = eventQueue.pop() {
            switch event {
            case .attention(let kind):
                send(.attention, payload: [("hook", .string(kind))])
                holdOutstanding = true
                heartbeat.start()
            case .resume:
                send(.resume, payload: [])
                holdOutstanding = false
                heartbeat.stop()
            }
        }
    }

    private func send(_ type: ProtocolMessageType, payload: [(String, JSONValue)]) {
        let nonce = (0..<16).map { _ in UInt8.random(in: 0...255) }
                             .map { String(format: "%02x", $0) }.joined()
        let msg = ProtocolMessage(
            version: 1, type: type,
            timestamp: Int64(Date().timeIntervalSince1970),
            nonceHex: nonce, payload: payload
        )
        peer.send(msg)
    }

    private func sendResync() { send(.resync, payload: []) }
    private func sendHeartbeat() { send(.heartbeat, payload: []) }

    private func handleInbound(_ msg: ProtocolMessage) {
        switch msg.type {
        case .pong:
            heartbeat.recordPong()
            if case let .bool(phoneHold)? = msg.payload.first(where: { $0.0 == "hold" })?.1 {
                holdOutstanding = phoneHold
                if !phoneHold { heartbeat.stop() }
            }
        case .ack, .invalidate:
            break
        default:
            break
        }
    }
}
