import Foundation

final class ConfigWatcher {
    private let path: String
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private let queue = DispatchQueue(label: "com.snapback.configWatcher")
    private let onChange: () -> Void
    /// Closure returning the timestamp of the most recent write we made.
    private let lastOwnWriteAt: () -> Date?

    init(path: String, onChange: @escaping () -> Void, lastOwnWriteAt: @escaping () -> Date?) {
        self.path = path
        self.onChange = onChange
        self.lastOwnWriteAt = lastOwnWriteAt
        start()
    }

    deinit { stop() }

    private func start() {
        fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend],
            queue: queue
        )
        src.setEventHandler { [weak self] in
            guard let self = self else { return }
            // Echo-suppress writes we made ourselves.
            if let ts = self.lastOwnWriteAt(), Date().timeIntervalSince(ts) < 0.5 {
                // Still re-arm on rename/delete
                self.rearmIfNeeded(src: src)
                return
            }
            self.onChange()
            self.rearmIfNeeded(src: src)
        }
        src.setCancelHandler { [weak self] in
            guard let self = self, self.fd >= 0 else { return }
            close(self.fd)
            self.fd = -1
        }
        src.resume()
        self.source = src
    }

    private func rearmIfNeeded(src: DispatchSourceFileSystemObject) {
        // Atomic renames replace the inode, so our fd becomes stale.
        // Cancel + restart on rename/delete.
        let data = src.data
        if data.contains(.rename) || data.contains(.delete) {
            stop()
            // Small delay so the new file is settled before we reopen.
            queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.start()
            }
        }
    }

    func stop() {
        source?.cancel()
        source = nil
    }
}
