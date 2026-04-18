import Foundation

public final class HeartbeatLoop {
    public var onPing: (() -> Void)?
    public var onDeadPeer: (() -> Void)?

    private let interval: TimeInterval
    private let missesBeforeDead: Int
    private let queue = DispatchQueue(label: "com.snapback.bridge.heartbeat")
    private var timer: DispatchSourceTimer?
    private var missesSinceLastPong = 0

    public init(intervalSeconds: TimeInterval = 30, missesBeforeDead: Int = 2) {
        self.interval = intervalSeconds
        self.missesBeforeDead = missesBeforeDead
    }

    public func start() {
        queue.async { [weak self] in self?.restartTimer() }
    }

    public func stop() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
        }
    }

    public func recordPong() {
        queue.async { [weak self] in self?.missesSinceLastPong = 0 }
    }

    private func restartTimer() {
        timer?.cancel()
        missesSinceLastPong = 0
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + interval, repeating: interval)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            self.missesSinceLastPong += 1
            if self.missesSinceLastPong >= self.missesBeforeDead {
                self.onDeadPeer?()
                return
            }
            self.onPing?()
        }
        t.resume()
        timer = t
    }
}
