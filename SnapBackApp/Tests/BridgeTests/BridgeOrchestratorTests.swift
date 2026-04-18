import XCTest
@testable import SnapBackApp

final class BridgeOrchestratorTests: XCTestCase {
    func testAttentionEventIsSentToPhone() throws {
        let secret = Data(repeating: 0x42, count: 32)
        let phone = try TestFakePhone(secret: secret); try phone.start()
        defer { phone.stop() }
        var port: UInt16 = 0
        for _ in 0..<40 {
            if let p = phone.actualPort, p > 0 { port = p; break }
            Thread.sleep(forTimeInterval: 0.025)
        }
        XCTAssertGreaterThan(port, 0)

        let queue = EventQueue()
        let peer = MobilePeer(host: "127.0.0.1", port: port,
                              secret: secret, peerName: "orch")
        let orch = BridgeOrchestrator(
            eventQueue: queue, peer: peer, status: BridgeStatusPublisher()
        )
        orch.start()
        defer { orch.stop() }

        // Wait for hello handshake to land.
        for _ in 0..<80 {
            if phone.receivedTypes.contains("hello") { break }
            Thread.sleep(forTimeInterval: 0.025)
        }
        queue.enqueue(.attention(kind: "Stop"))

        for _ in 0..<80 {
            if phone.receivedTypes.contains("attention") { break }
            Thread.sleep(forTimeInterval: 0.025)
        }
        XCTAssertTrue(phone.receivedTypes.contains("attention"))
        XCTAssertNil(phone.failureReason)
    }

    func testResumeEventIsSentToPhone() throws {
        let secret = Data(repeating: 0x42, count: 32)
        let phone = try TestFakePhone(secret: secret); try phone.start()
        defer { phone.stop() }
        var port: UInt16 = 0
        for _ in 0..<40 {
            if let p = phone.actualPort, p > 0 { port = p; break }
            Thread.sleep(forTimeInterval: 0.025)
        }
        let queue = EventQueue()
        let peer = MobilePeer(host: "127.0.0.1", port: port, secret: secret, peerName: "orch")
        let orch = BridgeOrchestrator(eventQueue: queue, peer: peer, status: BridgeStatusPublisher())
        orch.start()
        defer { orch.stop() }

        for _ in 0..<80 {
            if phone.receivedTypes.contains("hello") { break }
            Thread.sleep(forTimeInterval: 0.025)
        }
        queue.enqueue(.resume)
        for _ in 0..<80 {
            if phone.receivedTypes.contains("resume") { break }
            Thread.sleep(forTimeInterval: 0.025)
        }
        XCTAssertTrue(phone.receivedTypes.contains("resume"))
        XCTAssertNil(phone.failureReason)
    }

    // Regression: a `pong` reporting `hold: true` while the Mac thinks HOLD
    // is clear must (re)start the heartbeat loop, not silently leave it off.
    // We feed a synthetic pong through the peer's onMessage callback without
    // ever connecting a real socket.
    func testPongWithHoldTrueStartsHeartbeat() {
        let peer = MobilePeer(host: "127.0.0.1", port: 65530,
                              secret: Data(repeating: 0, count: 32), peerName: "stub")
        let hb = HeartbeatLoop(intervalSeconds: 0.05, missesBeforeDead: 100)
        let orch = BridgeOrchestrator(
            eventQueue: EventQueue(),
            peer: peer,
            status: BridgeStatusPublisher(),
            heartbeat: hb
        )
        _ = orch  // orchestrator installs onMessage + onPing during init

        // Wrap the orchestrator's onPing so we can observe firings without
        // stealing the handler from the orchestrator itself.
        var pinged = 0
        let original = hb.onPing
        hb.onPing = {
            original?()
            pinged += 1
        }

        let msg = ProtocolMessage(
            version: 1, type: .pong, timestamp: 1,
            nonceHex: String(repeating: "0", count: 32),
            payload: [("hold", .bool(true))]
        )
        peer.onMessage?(msg)

        Thread.sleep(forTimeInterval: 0.25)
        XCTAssertGreaterThan(pinged, 0, "heartbeat should run after pong{hold:true}")
    }
}
