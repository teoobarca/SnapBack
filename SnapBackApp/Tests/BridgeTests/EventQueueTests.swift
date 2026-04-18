import XCTest
@testable import SnapBackApp

final class EventQueueTests: XCTestCase {
    func testEnqueueDequeueFIFO() {
        let q = EventQueue(capacity: 4)
        q.enqueue(.attention(kind: "Stop"))
        q.enqueue(.resume)
        XCTAssertEqual(q.depth, 2)
        XCTAssertEqual(q.pop(), BridgeEvent.attention(kind: "Stop"))
        XCTAssertEqual(q.pop(), .resume)
        XCTAssertNil(q.pop())
    }

    func testBoundedCapacityDropsOldest() {
        let q = EventQueue(capacity: 2)
        q.enqueue(.attention(kind: "A"))
        q.enqueue(.attention(kind: "B"))
        q.enqueue(.attention(kind: "C"))
        XCTAssertEqual(q.depth, 2)
        XCTAssertEqual(q.pop(), .attention(kind: "B"))
        XCTAssertEqual(q.pop(), .attention(kind: "C"))
    }

    func testBackoffSchedule() {
        XCTAssertEqual(RetryPolicy.nextDelay(attemptsSoFar: 0), 0.5)
        XCTAssertEqual(RetryPolicy.nextDelay(attemptsSoFar: 1), 2.0)
        XCTAssertEqual(RetryPolicy.nextDelay(attemptsSoFar: 2), 8.0)
        XCTAssertNil(RetryPolicy.nextDelay(attemptsSoFar: 3))
    }
}
