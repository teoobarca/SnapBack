import XCTest
@testable import SnapBackApp

final class PairingTests: XCTestCase {
    func testPairingURLShape() {
        let token = Data((0..<32).map { UInt8($0) })
        let url = Pairing.pairingURL(token: token, deskName: "Hamper's MBP")
        XCTAssertTrue(url.hasPrefix("snapback-pair://v1?token="))
        XCTAssertTrue(url.contains("&desk=Hamper%27s%20MBP"))
        XCTAssertTrue(url.contains("&v=1"))
        // token hex is 64 chars
        let tokenPart = url
            .replacingOccurrences(of: "snapback-pair://v1?token=", with: "")
            .components(separatedBy: "&")
            .first!
        XCTAssertEqual(tokenPart.count, 64)
    }

    func testQRGeneratesSomeImage() {
        let url = "snapback-pair://v1?token=0000000000000000000000000000000000000000000000000000000000000000&v=1"
        let img = Pairing.qrImage(for: url)
        XCTAssertNotNil(img)
        XCTAssertGreaterThan(img!.width, 0)
        XCTAssertGreaterThan(img!.height, 0)
    }
}
