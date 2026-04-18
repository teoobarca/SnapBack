import Foundation
import Network
@testable import SnapBackApp

/// In-process TCP peer used by Swift tests. Accepts one or more connections,
/// verifies incoming HMACs against a shared secret, and replies to `hello`
/// with `ack`, to `heartbeat` with `pong`, and to `resync` with a `pong`
/// carrying a synthetic hold state.
final class TestFakePhone {
    let secret: Data
    private let requestedPort: UInt16
    private var listener: NWListener?
    private(set) var failureReason: String?
    private(set) var receivedTypes: [String] = []
    private let syncQueue = DispatchQueue(label: "com.snapback.test.fakephone")

    init(port: UInt16 = 0, secret: Data) throws {
        self.requestedPort = port
        self.secret = secret
    }

    func start() throws {
        let port: NWEndpoint.Port = requestedPort == 0 ? .any : NWEndpoint.Port(rawValue: requestedPort)!
        let listener = try NWListener(using: .tcp, on: port)
        listener.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
        listener.start(queue: .global(qos: .userInitiated))
        self.listener = listener
    }

    var actualPort: UInt16? {
        listener?.port?.rawValue
    }

    func stop() { listener?.cancel() }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .global(qos: .userInitiated))
        var buffer = Data()
        func loop() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
                [weak self] data, _, isComplete, _ in
                guard let self else { return }
                if let data, !data.isEmpty {
                    buffer.append(data)
                    while let nl = buffer.firstIndex(of: 0x0A) {
                        let line = String(data: buffer[..<nl], encoding: .utf8) ?? ""
                        buffer.removeSubrange(...nl)
                        self.process(line: line, on: conn)
                    }
                }
                if isComplete { conn.cancel(); return }
                loop()
            }
        }
        loop()
    }

    private func process(line: String, on conn: NWConnection) {
        do {
            let (msg, hmac) = try MessageCodec.decodeLine(line + "\n")
            guard MessageCodec.verify(message: msg, direction: .clientToServer,
                                      hmacHex: hmac, secret: secret) else {
                syncQueue.sync { self.failureReason = "bad hmac for \(msg.type.rawValue)" }
                return
            }
            syncQueue.sync { self.receivedTypes.append(msg.type.rawValue) }
            switch msg.type {
            case .hello:
                respond(type: .ack, payload: [], on: conn)
            case .heartbeat:
                respond(type: .pong, payload: [("hold", .bool(false))], on: conn)
            case .resync:
                respond(type: .pong, payload: [("hold", .bool(false))], on: conn)
            default:
                break
            }
        } catch {
            syncQueue.sync { self.failureReason = "\(error)" }
        }
    }

    private func respond(type: ProtocolMessageType,
                         payload: [(String, JSONValue)],
                         on conn: NWConnection) {
        let nonce = (0..<16).map { _ in UInt8.random(in: 0...255) }
                             .map { String(format: "%02x", $0) }.joined()
        let msg = ProtocolMessage(
            version: 1, type: type, timestamp: Int64(Date().timeIntervalSince1970),
            nonceHex: nonce, payload: payload
        )
        if let line = try? MessageCodec.encodeSignedLine(msg, direction: .serverToClient, secret: secret) {
            conn.send(content: Data(line.utf8), completion: .idempotent)
        }
    }
}
