import Foundation

public enum BridgeEvent: Equatable {
    case attention(kind: String)   // "PermissionRequest" | "Stop"
    case resume
}

public enum RetryPolicy {
    public static func nextDelay(attemptsSoFar: Int) -> TimeInterval? {
        switch attemptsSoFar {
        case 0: return 0.5
        case 1: return 2.0
        case 2: return 8.0
        default: return nil
        }
    }
}

public final class EventQueue {
    private let capacity: Int
    private var buffer: [BridgeEvent] = []
    private let queue = DispatchQueue(label: "com.snapback.bridge.eventQueue")

    public init(capacity: Int = 16) { self.capacity = capacity }

    public var depth: Int { queue.sync { buffer.count } }

    // NOTE (Phase 12): drop-oldest is a naive policy for *stateful* events.
    // If [attention, resume] overflows capacity 1, dropping "attention" leaves
    // the phone receiving "resume" for a HOLD it never saw. BridgeOrchestrator
    // must either enlarge capacity past realistic bursts or implement a
    // coalescing policy (e.g., "latest intent wins: depth <= 1").
    public func enqueue(_ event: BridgeEvent) {
        queue.sync {
            buffer.append(event)
            while buffer.count > capacity { buffer.removeFirst() }
        }
    }

    public func pop() -> BridgeEvent? {
        queue.sync { buffer.isEmpty ? nil : buffer.removeFirst() }
    }

    public func peek() -> BridgeEvent? {
        queue.sync { buffer.first }
    }
}
