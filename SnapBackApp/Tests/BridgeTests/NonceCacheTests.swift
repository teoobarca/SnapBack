import XCTest
@testable import SnapBackApp

final class NonceCacheTests: XCTestCase {
    func testAcceptsFirstOccurrence() {
        let cache = NonceCache(capacity: 8, ttlSeconds: 600)
        XCTAssertTrue(cache.tryAdd("n1", at: 100))
    }

    func testRejectsDuplicateWithinTTL() {
        let cache = NonceCache(capacity: 8, ttlSeconds: 600)
        _ = cache.tryAdd("n1", at: 100)
        XCTAssertFalse(cache.tryAdd("n1", at: 101))
    }

    func testAcceptsAfterTTL() {
        let cache = NonceCache(capacity: 8, ttlSeconds: 600)
        _ = cache.tryAdd("n1", at: 100)
        XCTAssertTrue(cache.tryAdd("n1", at: 701))
    }

    func testEvictsOldestWhenOverCapacity() {
        let cache = NonceCache(capacity: 2, ttlSeconds: 600)
        _ = cache.tryAdd("a", at: 100)
        _ = cache.tryAdd("b", at: 101)
        _ = cache.tryAdd("c", at: 102)
        // "a" should be gone, so re-adding it is accepted.
        XCTAssertTrue(cache.tryAdd("a", at: 103))
    }
}
