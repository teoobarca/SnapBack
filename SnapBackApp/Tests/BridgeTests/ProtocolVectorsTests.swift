import XCTest
@testable import SnapBackApp

final class ProtocolVectorsTests: XCTestCase {
    struct Fixture: Decodable {
        let v: Int
        let secret_hex: String
        let vectors: [Vector]

        struct Vector: Decodable {
            let name: String
            let direction: String
            let message: MessageBody
            let expected_hmac_hex: String?
        }
        struct MessageBody: Decodable {
            let v: Int
            let type: String
            let ts: Int64
            let nonce: String
            let payload: [String: JSONAny]
        }
    }

    struct JSONAny: Decodable {
        let raw: Any
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let b = try? c.decode(Bool.self)   { raw = b; return }
            if let i = try? c.decode(Int64.self)  { raw = i; return }
            if let d = try? c.decode(Double.self) { raw = d; return }
            if let s = try? c.decode(String.self) { raw = s; return }
            if c.decodeNil()                      { raw = NSNull(); return }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "unsupported")
        }
    }

    func testAllVectorsRoundTrip() throws {
        let url = Bundle.module.url(forResource: "protocol-vectors", withExtension: "json",
                                    subdirectory: "fixtures")!
        let data = try Data(contentsOf: url)
        let fx = try JSONDecoder().decode(Fixture.self, from: data)
        let secret = Data(hex: fx.secret_hex)!

        for v in fx.vectors {
            let payload = v.message.payload
                .sorted { $0.key < $1.key }
                .map { ($0.key, try! JSONValue.fromAny($0.value.raw)) }
            let direction = ProtocolDirection(rawValue: v.direction)!
            let type = ProtocolMessageType(rawValue: v.message.type)!
            let msg = ProtocolMessage(
                version: v.message.v,
                type: type,
                timestamp: v.message.ts,
                nonceHex: v.message.nonce,
                payload: payload
            )
            let line = try MessageCodec.encodeSignedLine(msg, direction: direction, secret: secret)
            let (decoded, hmac) = try MessageCodec.decodeLine(line)
            XCTAssertEqual(decoded, msg, "\(v.name) round-trip mismatch")
            XCTAssertTrue(
                MessageCodec.verify(message: decoded, direction: direction, hmacHex: hmac, secret: secret),
                "\(v.name) verify failed"
            )
        }
    }
}

extension ProtocolVectorsTests {
    /// Assert that each vector in the fixture has an `expected_hmac_hex` field
    /// matching a fresh sign. If the fixture lacks the field, this test fails
    /// with a clear message instructing how to regenerate.
    func testAllVectorsCarryPrecomputedHMACs() throws {
        let url = Bundle.module.url(forResource: "protocol-vectors",
                                    withExtension: "json",
                                    subdirectory: "fixtures")!
        let data = try Data(contentsOf: url)
        let fx = try JSONDecoder().decode(Fixture.self, from: data)
        let secret = Data(hex: fx.secret_hex)!

        for v in fx.vectors {
            let payload = v.message.payload
                .sorted { $0.key < $1.key }
                .map { ($0.key, try! JSONValue.fromAny($0.value.raw)) }
            let direction = ProtocolDirection(rawValue: v.direction)!
            let type = ProtocolMessageType(rawValue: v.message.type)!
            let msg = ProtocolMessage(
                version: v.message.v, type: type, timestamp: v.message.ts,
                nonceHex: v.message.nonce, payload: payload
            )
            let actual = MessageCodec.sign(message: msg, direction: direction, secret: secret)
            guard let expected = v.expected_hmac_hex else {
                XCTFail("""
                    Fixture vector '\(v.name)' is missing expected_hmac_hex.
                    Add this to tests/protocol-vectors.json (both copies):
                        "expected_hmac_hex": "\(actual)"
                    """)
                continue
            }
            XCTAssertEqual(expected, actual,
                           "HMAC mismatch for vector '\(v.name)' — did the signing domain change?")
        }
    }
}
