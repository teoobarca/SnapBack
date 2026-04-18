import XCTest
@testable import SnapBackApp

final class MessageCodecTypesTests: XCTestCase {
    func testMessageTypeExists() {
        let message = ProtocolMessage(
            version: 1,
            type: .attention,
            timestamp: 1_734_556_677,
            nonceHex: String(repeating: "a", count: 32),
            payload: [("hook", .string("PermissionRequest"))]
        )
        XCTAssertEqual(message.version, 1)
        XCTAssertEqual(message.type, .attention)
    }

    func testDirectionEnumCoversBothSides() {
        XCTAssertEqual(ProtocolDirection.clientToServer.rawValue, "c2s")
        XCTAssertEqual(ProtocolDirection.serverToClient.rawValue, "s2c")
    }
}

final class CanonicalJSONTests: XCTestCase {
    func testObjectKeysSortedAlphabetically() {
        let payload: [(String, JSONValue)] = [
            ("b", .int(2)),
            ("a", .int(1))
        ]
        let bytes = CanonicalJSON.encode(.object(payload))
        XCTAssertEqual(String(data: bytes, encoding: .utf8), "{\"a\":1,\"b\":2}")
    }

    func testEmptyObject() {
        let bytes = CanonicalJSON.encode(.object([]))
        XCTAssertEqual(String(data: bytes, encoding: .utf8), "{}")
    }

    func testEscaping() {
        let bytes = CanonicalJSON.encode(.string("a\"b\\c\n"))
        XCTAssertEqual(String(data: bytes, encoding: .utf8), "\"a\\\"b\\\\c\\n\"")
    }

    func testIntegersNoFraction() {
        let bytes = CanonicalJSON.encode(.int(0))
        XCTAssertEqual(String(data: bytes, encoding: .utf8), "0")
    }

    func testBooleansAndNull() {
        XCTAssertEqual(String(data: CanonicalJSON.encode(.bool(true)),  encoding: .utf8), "true")
        XCTAssertEqual(String(data: CanonicalJSON.encode(.bool(false)), encoding: .utf8), "false")
        XCTAssertEqual(String(data: CanonicalJSON.encode(.null),        encoding: .utf8), "null")
    }
}
