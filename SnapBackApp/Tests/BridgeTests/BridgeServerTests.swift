import XCTest
@testable import SnapBackApp

final class BridgeServerParserTests: XCTestCase {
    func testParsesAttentionWithKind() {
        let ev = BridgeServer.parseLine("attention\tStop")
        XCTAssertEqual(ev, .attention(kind: "Stop"))
    }

    func testParsesAttentionWithoutKind() {
        let ev = BridgeServer.parseLine("attention")
        XCTAssertEqual(ev, .attention(kind: "Stop"))
    }

    func testParsesResume() {
        let ev = BridgeServer.parseLine("resume")
        XCTAssertEqual(ev, .resume)
    }

    func testReturnsNilForUnknown() {
        XCTAssertNil(BridgeServer.parseLine("bogus"))
        XCTAssertNil(BridgeServer.parseLine(""))
    }
}
