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
