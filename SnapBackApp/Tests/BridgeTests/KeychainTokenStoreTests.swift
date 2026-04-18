import XCTest
@testable import SnapBackApp

final class KeychainTokenStoreTests: XCTestCase {
    private func testStore() -> KeychainTokenStore {
        KeychainTokenStore(service: "com.snapback.mobile.test.\(UUID().uuidString)",
                           account: "pair-token")
    }

    func testReadReturnsNilWhenAbsent() {
        let store = testStore()
        XCTAssertNil(store.read())
    }

    func testGenerateAndReadRoundTrip() throws {
        let store = testStore()
        defer { try? store.delete() }
        let token = try store.generateAndStore()
        XCTAssertEqual(token.count, 32)
        let read = store.read()
        XCTAssertEqual(read, token)
    }

    func testDeleteRemovesEntry() throws {
        let store = testStore()
        _ = try store.generateAndStore()
        try store.delete()
        XCTAssertNil(store.read())
    }
}
