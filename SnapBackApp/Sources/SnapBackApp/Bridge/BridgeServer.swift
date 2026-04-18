import Foundation
import Darwin

// MARK: - Error types

public enum BridgeServerError: Error {
    case bindFailed(Int32)
    case listenFailed(Int32)
}

// MARK: - BridgeServer

/// Listens on a Unix-domain socket, parses newline-delimited lines written by
/// `snapback-poke`, and feeds resulting `BridgeEvent`s into the `EventQueue`.
///
/// Implementation uses POSIX sockets for portability across macOS SDK versions.
/// Network.framework UDS endpoint APIs are not stable across the macOS 13–14
/// boundary that this package targets, so POSIX is the correct choice here.
public final class BridgeServer {

    // MARK: Parser (pure, no IO) — Task 10.1

    /// Parses a single TSV line into a `BridgeEvent`.
    ///
    /// - `"attention"` → `.attention(kind: "Stop")` (default kind)
    /// - `"attention\tPermissionRequest"` → `.attention(kind: "PermissionRequest")`
    /// - `"resume"` → `.resume`
    /// - empty / unknown → `nil`
    public static func parseLine(_ raw: String) -> BridgeEvent? {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty { return nil }
        let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
        switch parts[0] {
        case "attention":
            let kind = parts.count > 1 ? String(parts[1]) : "Stop"
            return .attention(kind: kind)
        case "resume":
            return .resume
        default:
            return nil
        }
    }

    // MARK: UDS listener — Task 10.2

    private var socketPath: String = ""
    private var eventQueue: EventQueue?
    private var log: BridgeLog?
    // `listenFD` and `running` are written from the main/stopping thread and
    // read from the accept thread. Darwin word-sized reads are tear-free in
    // practice; a close() on the listening fd causes the blocking accept() to
    // return with errno EBADF, which is how we unblock shutdown. Documented
    // here to keep Phase 12's BridgeOrchestrator honest.
    private var listenFD: Int32 = -1
    private var acceptThread: Thread?
    private var running = false

    /// Max per-connection buffered bytes before a line arrives. Caps worst-case
    /// memory for a misbehaving local client that never writes LF.
    private static let perClientBufferCap: Int = 64 * 1024

    /// Invoked after the accept loop exits (either cleanly via `stop()` or due
    /// to a fatal errno from `accept()`). Lets Phase 12 mark the bridge
    /// unhealthy / restart.
    public var onTerminate: ((Int32?) -> Void)?

    public init() {}

    public convenience init(socketPath: String, eventQueue: EventQueue, log: BridgeLog) {
        self.init()
        self.socketPath = socketPath
        self.eventQueue = eventQueue
        self.log = log
    }

    /// Start the UDS listener. Removes any stale socket file first.
    /// Returns immediately; the accept loop runs on a background thread.
    public func start() throws {
        unlink(socketPath)  // remove stale socket, ignore errors

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        if fd < 0 { throw BridgeServerError.bindFailed(errno) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { ptr in
            withUnsafeMutableBytes(of: &addr.sun_path) { buf in
                let n = min(strlen(ptr), buf.count - 1)
                buf.baseAddress!.copyMemory(from: UnsafeRawPointer(ptr), byteCount: n)
                buf.baseAddress!.advanced(by: n)
                    .assumingMemoryBound(to: CChar.self).pointee = 0
            }
        }

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if bindResult != 0 {
            let err = errno
            Darwin.close(fd)
            throw BridgeServerError.bindFailed(err)
        }

        if Darwin.listen(fd, 8) != 0 {
            let err = errno
            Darwin.close(fd)
            throw BridgeServerError.listenFailed(err)
        }

        listenFD = fd
        running = true

        let t = Thread { [weak self] in self?.acceptLoop() }
        t.name = "com.snapback.bridge.accept"
        acceptThread = t
        t.start()
    }

    /// Stop the listener: closes the socket and removes the socket file.
    public func stop() {
        running = false
        if listenFD >= 0 {
            Darwin.close(listenFD)
            listenFD = -1
        }
        unlink(socketPath)
    }

    // MARK: Private

    private func acceptLoop() {
        var lastErrno: Int32? = nil
        while running {
            let client = Darwin.accept(listenFD, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                lastErrno = errno
                break
            }
            handleClient(client)
        }
        if running {
            // Fell out of the loop while still supposed to be running — that's a fatal accept().
            log?.error("bridge accept loop terminated unexpectedly, errno=\(lastErrno ?? 0)")
        }
        onTerminate?(lastErrno)
    }

    private func handleClient(_ fd: Int32) {
        defer { Darwin.close(fd) }
        var buffer = [UInt8]()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = Darwin.read(fd, &chunk, chunk.count)
            if n <= 0 { break }
            buffer.append(contentsOf: chunk[0..<n])
            if buffer.count > BridgeServer.perClientBufferCap {
                log?.warn("bridge per-client buffer cap exceeded; dropping connection")
                return
            }
            // Drain any complete lines (terminated by LF 0x0A).
            while let nlIndex = buffer.firstIndex(of: 0x0A) {
                let lineBytes = Array(buffer[0..<nlIndex])
                buffer.removeFirst(nlIndex + 1)
                if let line = String(bytes: lineBytes, encoding: .utf8),
                   let event = BridgeServer.parseLine(line) {
                    eventQueue?.enqueue(event)
                    log?.info("bridge accepted event: \(event)")
                }
            }
        }
    }
}
