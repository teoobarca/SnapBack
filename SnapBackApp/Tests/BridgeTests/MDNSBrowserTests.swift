import XCTest
import Network
@testable import SnapBackApp

final class MDNSBrowserTests: XCTestCase {
    func testDiscoversLocalAdvertisement() throws {
        // Advertise a test service from another NWListener (this process).
        let listener = try NWListener(using: .tcp, on: .any)
        listener.service = NWListener.Service(
            name: "snapback-test-\(UUID().uuidString.prefix(8))",
            type: "_snapback._tcp",
            domain: "local.",
            txtRecord: nil
        )
        listener.newConnectionHandler = { _ in }
        listener.start(queue: .global(qos: .userInitiated))
        defer { listener.cancel() }

        let exp = expectation(description: "discovered")
        exp.assertForOverFulfill = false
        let browser = MDNSBrowser()
        browser.onDiscover = { host, port in
            if port > 0 { exp.fulfill() }
        }
        browser.start()
        wait(for: [exp], timeout: 10.0)
        browser.stop()
    }
}
