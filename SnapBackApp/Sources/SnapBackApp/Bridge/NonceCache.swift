import Foundation

/// Bounded TTL+LRU cache for replay protection.
/// Thread-safe via an internal serial queue.
public final class NonceCache {
    private let capacity: Int
    private let ttl: TimeInterval
    private var entries: [(nonce: String, insertedAt: TimeInterval)] = []
    private let queue = DispatchQueue(label: "com.snapback.bridge.nonceCache")

    public init(capacity: Int, ttlSeconds: TimeInterval) {
        self.capacity = capacity
        self.ttl = ttlSeconds
    }

    /// Returns `true` if the nonce was new and has now been recorded.
    /// `now` is expressed in unix seconds; the caller supplies it so tests are deterministic.
    public func tryAdd(_ nonce: String, at now: TimeInterval) -> Bool {
        queue.sync {
            entries.removeAll { now - $0.insertedAt > ttl }
            if entries.contains(where: { $0.nonce == nonce }) { return false }
            entries.append((nonce: nonce, insertedAt: now))
            while entries.count > capacity { entries.removeFirst() }
            return true
        }
    }
}
