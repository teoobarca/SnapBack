import XCTest
@testable import SnapBackApp

final class HeartbeatLoopTests: XCTestCase {
    func testFiresPingAtInterval() {
        var pings = 0
        let loop = HeartbeatLoop(intervalSeconds: 0.1, missesBeforeDead: 3)
        loop.onPing = { pings += 1 }
        loop.start()
        Thread.sleep(forTimeInterval: 0.35)
        loop.stop()
        XCTAssertGreaterThanOrEqual(pings, 2)
    }

    func testDeclaresDeadAfterMissedPongs() {
        let exp = expectation(description: "dead")
        let loop = HeartbeatLoop(intervalSeconds: 0.05, missesBeforeDead: 2)
        loop.onPing = { /* do not ack */ }
        loop.onDeadPeer = { exp.fulfill() }
        loop.start()
        wait(for: [exp], timeout: 2.0)
        loop.stop()
    }

    func testAckResetsMissCount() {
        let loop = HeartbeatLoop(intervalSeconds: 0.05, missesBeforeDead: 2)
        var deadCalls = 0
        loop.onDeadPeer = { deadCalls += 1 }
        loop.onPing = { loop.recordPong() }
        loop.start()
        Thread.sleep(forTimeInterval: 0.35)
        loop.stop()
        XCTAssertEqual(deadCalls, 0)
    }
}
