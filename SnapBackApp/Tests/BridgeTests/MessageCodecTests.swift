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

final class SigningDomainTests: XCTestCase {
    func testDomainHasDirectionFirstAndNullSeparators() {
        let msg = ProtocolMessage(
            version: 1,
            type: .attention,
            timestamp: 1_734_556_677,
            nonceHex: String(repeating: "0", count: 32),
            payload: [("hook", .string("Stop"))]
        )
        let domain = MessageCodec.signingDomain(for: msg, direction: .clientToServer)
        let expected: [UInt8] = Array(
            ("c2s\u{00}1\u{00}attention\u{00}1734556677\u{00}" +
             String(repeating: "0", count: 32) + "\u{00}" +
             "{\"hook\":\"Stop\"}").utf8
        )
        XCTAssertEqual(Array(domain), expected)
    }

    func testEmptyPayloadSerializesAsOpenClose() {
        let msg = ProtocolMessage(
            version: 1,
            type: .resume,
            timestamp: 100,
            nonceHex: String(repeating: "1", count: 32),
            payload: []
        )
        let domain = MessageCodec.signingDomain(for: msg, direction: .clientToServer)
        let domainStr = String(data: domain, encoding: .utf8)
        XCTAssertEqual(domainStr?.hasSuffix("\u{00}{}"), true)
    }
}
