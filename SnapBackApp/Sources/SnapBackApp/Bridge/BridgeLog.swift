import Foundation

public final class BridgeLog {
    private let directory: URL
    private let basename: String
    private let maxBytes: Int
    private let rotations: Int
    private let queue = DispatchQueue(label: "com.snapback.bridge.log")
    private var handle: FileHandle?
    private let formatter: DateFormatter

    public init(directory: URL,
                basename: String = "bridge.log",
                maxBytes: Int = 1_048_576,
                rotations: Int = 5) {
        self.directory = directory
        self.basename = basename
        self.maxBytes = maxBytes
        self.rotations = rotations
        self.formatter = DateFormatter()
        self.formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        self.formatter.locale = Locale(identifier: "en_US_POSIX")
    }

    public func info(_ message: String) { write("INFO", message) }
    public func warn(_ message: String) { write("WARN", message) }
    public func error(_ message: String) { write("ERROR", message) }

    private func write(_ level: String, _ message: String) {
        let line = "\(formatter.string(from: Date())) [\(level)] \(message)\n"
        queue.async { [weak self] in
            guard let self else { return }
            try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            let url = self.directory.appendingPathComponent(self.basename)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            if self.handle == nil {
                self.handle = try? FileHandle(forWritingTo: url)
                try? self.handle?.seekToEnd()
            }
            self.handle?.write(Data(line.utf8))
            self.rotateIfNeeded(url: url)
        }
    }

    public func flush() {
        queue.sync { try? handle?.synchronize() }
    }

    private func rotateIfNeeded(url: URL) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int,
              size >= maxBytes else { return }
        handle?.closeFile()
        handle = nil
        for i in stride(from: rotations - 1, through: 1, by: -1) {
            let src = directory.appendingPathComponent("\(basename).\(i)")
            let dst = directory.appendingPathComponent("\(basename).\(i+1)")
            _ = try? FileManager.default.removeItem(at: dst)
            _ = try? FileManager.default.moveItem(at: src, to: dst)
        }
        let firstRotation = directory.appendingPathComponent("\(basename).1")
        _ = try? FileManager.default.removeItem(at: firstRotation)
        _ = try? FileManager.default.moveItem(at: url, to: firstRotation)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try? FileHandle(forWritingTo: url)
        try? handle?.seekToEnd()
    }
}
