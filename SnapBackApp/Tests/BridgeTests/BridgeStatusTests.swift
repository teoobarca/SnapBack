import XCTest
import Combine
@testable import SnapBackApp

final class BridgeStatusTests: XCTestCase {
    func testInitialStatusIsUnpaired() {
        let s = BridgeStatusPublisher()
        XCTAssertEqual(s.current, .unpaired)
    }

    func testUpdatePropagates() {
        let s = BridgeStatusPublisher()
        let exp = expectation(description: "status update")
        var cancellables = Set<AnyCancellable>()
        s.$current
          .dropFirst()
          .sink { status in
              if status == .connected { exp.fulfill() }
          }
          .store(in: &cancellables)
        s.update(.connected)
        wait(for: [exp], timeout: 1.0)
    }
}
