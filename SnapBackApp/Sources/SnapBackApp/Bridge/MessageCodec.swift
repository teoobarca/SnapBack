import CryptoKit
import Foundation

/// Direction of a signed message on the wire. Used as the first segment of the HMAC domain.
public enum ProtocolDirection: String {
    case clientToServer = "c2s"
    case serverToClient = "s2c"
}

/// The fixed set of message types in protocol v1.
public enum ProtocolMessageType: String, CaseIterable {
    case hello
    case ack
    case attention
    case resume
    case heartbeat
    case pong
    case resync
    case invalidate
}

/// A canonical, serializable JSON value type.
/// Using a bespoke enum (rather than `Any`) guarantees deterministic serialization.
public indirect enum JSONValue {
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([(String, JSONValue)]) // ordered; canonical serializer sorts by key
}

extension JSONValue: Equatable {
    public static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.string(let a), .string(let b)): return a == b
        case (.int(let a), .int(let b)): return a == b
        case (.double(let a), .double(let b)): return a == b
        case (.bool(let a), .bool(let b)): return a == b
        case (.null, .null): return true
        case (.array(let a), .array(let b)): return a == b
        case (.object(let a), .object(let b)):
            guard a.count == b.count else { return false }
            for (ai, bi) in zip(a, b) {
                if ai.0 != bi.0 || ai.1 != bi.1 { return false }
            }
            return true
        default: return false
        }
    }
}

/// A protocol v1 message, language-agnostic shape.
public struct ProtocolMessage: Equatable {
    public var version: Int
    public var type: ProtocolMessageType
    public var timestamp: Int64
    public var nonceHex: String                // exactly 32 lowercase hex chars
    public var payload: [(String, JSONValue)]  // may be empty

    public init(version: Int,
                type: ProtocolMessageType,
                timestamp: Int64,
                nonceHex: String,
                payload: [(String, JSONValue)] = []) {
        self.version = version
        self.type = type
        self.timestamp = timestamp
        self.nonceHex = nonceHex
        self.payload = payload
    }

    public static func == (lhs: ProtocolMessage, rhs: ProtocolMessage) -> Bool {
        lhs.version == rhs.version &&
        lhs.type == rhs.type &&
        lhs.timestamp == rhs.timestamp &&
        lhs.nonceHex == rhs.nonceHex &&
        lhs.payload.map { $0.0 } == rhs.payload.map { $0.0 } &&
        lhs.payload.map { $0.1 } == rhs.payload.map { $0.1 }
    }
}

// MARK: - CanonicalJSON

/// Deterministic JSON encoder. The spec's HMAC domain (§4.1) requires byte-for-byte
/// reproducibility across implementations. This encoder therefore:
///   • sorts object keys (lexicographic on the UTF-8 bytes)
///   • emits integers as shortest decimal
///   • emits doubles with the minimum representation that round-trips
///   • escapes strings with only the six required backslash escapes and \uXXXX for
///     control chars
///   • emits no whitespace
public enum CanonicalJSON {
    public static func encode(_ value: JSONValue) -> Data {
        var out = Data()
        append(value, to: &out)
        return out
    }

    private static func append(_ value: JSONValue, to out: inout Data) {
        switch value {
        case .null:
            out.append(contentsOf: "null".utf8)
        case .bool(let b):
            out.append(contentsOf: (b ? "true" : "false").utf8)
        case .int(let i):
            out.append(contentsOf: String(i).utf8)
        case .double(let d):
            // Use Swift's default repr which is the shortest round-trip.
            out.append(contentsOf: String(d).utf8)
        case .string(let s):
            appendString(s, to: &out)
        case .array(let arr):
            out.append(UInt8(ascii: "["))
            for (idx, v) in arr.enumerated() {
                if idx > 0 { out.append(UInt8(ascii: ",")) }
                append(v, to: &out)
            }
            out.append(UInt8(ascii: "]"))
        case .object(let pairs):
            let sorted = pairs.sorted { $0.0 < $1.0 }
            out.append(UInt8(ascii: "{"))
            for (idx, kv) in sorted.enumerated() {
                if idx > 0 { out.append(UInt8(ascii: ",")) }
                appendString(kv.0, to: &out)
                out.append(UInt8(ascii: ":"))
                append(kv.1, to: &out)
            }
            out.append(UInt8(ascii: "}"))
        }
    }

    private static func appendString(_ s: String, to out: inout Data) {
        out.append(UInt8(ascii: "\""))
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out.append(contentsOf: "\\\"".utf8)
            case "\\": out.append(contentsOf: "\\\\".utf8)
            case "\u{08}": out.append(contentsOf: "\\b".utf8)
            case "\u{09}": out.append(contentsOf: "\\t".utf8)
            case "\u{0A}": out.append(contentsOf: "\\n".utf8)
            case "\u{0C}": out.append(contentsOf: "\\f".utf8)
            case "\u{0D}": out.append(contentsOf: "\\r".utf8)
            default:
                if scalar.value < 0x20 {
                    out.append(contentsOf: String(format: "\\u%04x", scalar.value).utf8)
                } else {
                    out.append(contentsOf: String(scalar).utf8)
                }
            }
        }
        out.append(UInt8(ascii: "\""))
    }
}

// MARK: - MessageCodec

public enum MessageCodec {
    /// Returns the exact bytes fed into HMAC-SHA256. See spec §4.1 signing domain.
    public static func signingDomain(for message: ProtocolMessage,
                                     direction: ProtocolDirection) -> Data {
        var out = Data()
        out.append(contentsOf: direction.rawValue.utf8)
        out.append(0x00)
        out.append(contentsOf: String(message.version).utf8)
        out.append(0x00)
        out.append(contentsOf: message.type.rawValue.utf8)
        out.append(0x00)
        out.append(contentsOf: String(message.timestamp).utf8)
        out.append(0x00)
        out.append(contentsOf: message.nonceHex.utf8)
        out.append(0x00)
        out.append(CanonicalJSON.encode(.object(message.payload)))
        return out
    }

    public static func sign(message: ProtocolMessage,
                            direction: ProtocolDirection,
                            secret: Data) -> String {
        precondition(isValidNonceHex(message.nonceHex),
                     "nonceHex must be exactly 32 lowercase hex chars")
        let domain = signingDomain(for: message, direction: direction)
        let key = SymmetricKey(data: secret)
        let mac = HMAC<SHA256>.authenticationCode(for: domain, using: key)
        return Data(mac).map { String(format: "%02x", $0) }.joined()
    }

    public static func verify(message: ProtocolMessage,
                              direction: ProtocolDirection,
                              hmacHex: String,
                              secret: Data) -> Bool {
        guard let expected = Data(hex: hmacHex) else { return false }
        let domain = signingDomain(for: message, direction: direction)
        let key = SymmetricKey(data: secret)
        return HMAC<SHA256>.isValidAuthenticationCode(
            expected,
            authenticating: domain,
            using: key
        )
    }
}

// MARK: - MessageCodecError

public enum MessageCodecError: Error {
    case invalidJSON
    case missingField(String)
    case unknownType(String)
    case invalidNonce
    case invalidPayload
    case invalidVersion(Int)
}

// MARK: - Nonce validation

extension MessageCodec {
    /// Validates nonceHex per the wire format (exactly 32 lowercase hex chars).
    public static func isValidNonceHex(_ s: String) -> Bool {
        guard s.count == 32 else { return false }
        for c in s.unicodeScalars {
            switch c {
            case "0"..."9", "a"..."f": continue
            default: return false
            }
        }
        return true
    }
}

// MARK: - Wire encode/decode

extension MessageCodec {
    /// Encode `message` as a complete wire line (JSON + trailing `\n`), signed in `direction`.
    public static func encodeSignedLine(_ message: ProtocolMessage,
                                        direction: ProtocolDirection,
                                        secret: Data) throws -> String {
        precondition(isValidNonceHex(message.nonceHex),
                     "nonceHex must be exactly 32 lowercase hex chars")
        let hmac = sign(message: message, direction: direction, secret: secret)
        var body: [(String, JSONValue)] = [
            ("hmac", .string(hmac)),
            ("nonce", .string(message.nonceHex)),
            ("payload", .object(message.payload)),
            ("ts", .int(message.timestamp)),
            ("type", .string(message.type.rawValue)),
            ("v", .int(Int64(message.version)))
        ]
        body.sort { $0.0 < $1.0 }
        let data = CanonicalJSON.encode(.object(body))
        guard var s = String(data: data, encoding: .utf8) else { throw MessageCodecError.invalidJSON }
        s.append("\n")
        return s
    }

    /// Decode a wire line into `(message, hmac_hex)`. Verification is the caller's job.
    public static func decodeLine(_ line: String) throws -> (ProtocolMessage, String) {
        let trimmed = line.hasSuffix("\n") ? String(line.dropLast()) : line
        guard let data = trimmed.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data, options: []),
              let obj = any as? [String: Any] else {
            throw MessageCodecError.invalidJSON
        }
        guard let vNum = obj["v"] as? NSNumber else { throw MessageCodecError.missingField("v") }
        let v = vNum.intValue
        guard v == 1 else { throw MessageCodecError.invalidVersion(v) }
        guard let typeString = obj["type"] as? String else { throw MessageCodecError.missingField("type") }
        guard let type = ProtocolMessageType(rawValue: typeString) else {
            throw MessageCodecError.unknownType(typeString)
        }
        guard let tsNum = obj["ts"] as? NSNumber else { throw MessageCodecError.missingField("ts") }
        let ts = tsNum.int64Value
        guard let nonce = obj["nonce"] as? String, isValidNonceHex(nonce) else {
            throw MessageCodecError.invalidNonce
        }
        guard let hmac = obj["hmac"] as? String else { throw MessageCodecError.missingField("hmac") }
        let payloadAny = obj["payload"] ?? [String: Any]()
        guard let payloadDict = payloadAny as? [String: Any] else {
            throw MessageCodecError.invalidPayload
        }
        let payload: [(String, JSONValue)] = try payloadDict
            .sorted { $0.key < $1.key }
            .map { (k, v) in (k, try JSONValue.fromAny(v)) }

        let msg = ProtocolMessage(version: v, type: type, timestamp: ts,
                                  nonceHex: nonce, payload: payload)
        return (msg, hmac)
    }
}

// MARK: - JSONValue helpers

extension JSONValue {
    static func fromAny(_ any: Any) throws -> JSONValue {
        // NSNumber can encode Bool — check Bool before Int/Double to avoid mis-casting
        if let n = any as? NSNumber {
            // CFBooleanRef has ObjC type "c" (char) for Bool
            let typeID = CFGetTypeID(n)
            if typeID == CFBooleanGetTypeID() {
                return .bool(n.boolValue)
            }
            // Distinguish Int64 from Double by checking if it has a fractional part
            let d = n.doubleValue
            if d == Double(n.int64Value) && !d.isInfinite {
                return .int(n.int64Value)
            }
            return .double(d)
        }
        if let s = any as? String { return .string(s) }
        if any is NSNull { return .null }
        if let arr = any as? [Any] {
            return .array(try arr.map { try JSONValue.fromAny($0) })
        }
        if let obj = any as? [String: Any] {
            let pairs = try obj.sorted { $0.key < $1.key }
                               .map { ($0.key, try JSONValue.fromAny($0.value)) }
            return .object(pairs)
        }
        throw MessageCodecError.invalidPayload
    }
}

// MARK: - Data hex helpers

extension Data {
    /// Parses a string of exactly 2N lowercase hex characters. Rejects whitespace,
    /// uppercase, or any non-hex character. Returns nil on malformed input.
    init?(hex: String) {
        guard hex.count % 2 == 0 else { return nil }
        var buf = Data(capacity: hex.count / 2)
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let hi = hex[idx]
            let lo = hex[hex.index(after: idx)]
            guard
                let hiVal = Data.hexNibble(hi),
                let loVal = Data.hexNibble(lo)
            else { return nil }
            buf.append(hiVal << 4 | loVal)
            idx = hex.index(idx, offsetBy: 2)
        }
        self = buf
    }

    private static func hexNibble(_ c: Character) -> UInt8? {
        switch c {
        case "0"..."9": return UInt8(c.asciiValue! - 0x30)
        case "a"..."f": return UInt8(c.asciiValue! - 0x57)  // 'a' = 0x61, want 10
        default: return nil
        }
    }
}
