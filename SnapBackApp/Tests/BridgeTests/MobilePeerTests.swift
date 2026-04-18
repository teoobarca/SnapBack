import XCTest
import Network
@testable import SnapBackApp

final class MobilePeerTests: XCTestCase {
    func testHelloAckHandshake() throws {
        let secret = Data(repeating: 0x42, count: 32)
        let phone = try TestFakePhone(secret: secret); try phone.start()
        defer { phone.stop() }
        var port: UInt16 = 0
        for _ in 0..<20 {
            if let p = phone.actualPort, p > 0 { port = p; break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertGreaterThan(port, 0)

        let peer = MobilePeer(host: "127.0.0.1", port: port,
                              secret: secret, peerName: "HamperMBP")
        let exp = expectation(description: "ack received")
        peer.onStateChange = { state in
            if state == .connected { exp.fulfill() }
        }
        peer.start()
        wait(for: [exp], timeout: 3.0)
        peer.stop()
        // Give the fake phone a short moment to flush its receiver state.
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertTrue(phone.receivedTypes.contains("hello"))
        XCTAssertNil(phone.failureReason)
    }

    func testReconnectsAfterPhoneRestart() throws {
        let secret = Data(repeating: 0x42, count: 32)
        var phone = try TestFakePhone(secret: secret); try phone.start()
        var port: UInt16 = 0
        for _ in 0..<20 {
            if let p = phone.actualPort, p > 0 { port = p; break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertGreaterThan(port, 0)

        let peer = MobilePeer(host: "127.0.0.1", port: port, secret: secret, peerName: "t")
        let connectedOnce = expectation(description: "connected once")
        let connectedTwice = expectation(description: "connected again")
        var seen = 0
        peer.onStateChange = { s in
            if s == .connected {
                seen += 1
                if seen == 1 { connectedOnce.fulfill() }
                else if seen == 2 { connectedTwice.fulfill() }
            }
        }
        peer.start()
        wait(for: [connectedOnce], timeout: 3.0)

        phone.stop()
        Thread.sleep(forTimeInterval: 0.5)
        phone = try TestFakePhone(port: port, secret: secret)
        try phone.start()
        wait(for: [connectedTwice], timeout: 10.0)
        peer.stop()
        phone.stop()
    }
}
