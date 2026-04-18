import Foundation
import Combine

public enum BridgeStatus: Equatable {
    case unpaired
    case connecting
    case connected
    case unreachable
    case error(String)
}

public final class BridgeStatusPublisher: ObservableObject {
    @Published public private(set) var current: BridgeStatus = .unpaired

    public init() {}

    public func update(_ new: BridgeStatus) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.current != new { self.current = new }
        }
    }
}
