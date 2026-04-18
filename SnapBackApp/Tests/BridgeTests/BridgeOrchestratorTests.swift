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
}
