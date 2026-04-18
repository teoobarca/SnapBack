import XCTest
@testable import SnapBackApp

final class BridgeServerParserTests: XCTestCase {
    func testParsesAttentionWithKind() {
        let ev = BridgeServer.parseLine("attention\tStop")
        XCTAssertEqual(ev, .attention(kind: "Stop"))
    }

    func testParsesAttentionWithoutKind() {
        let ev = BridgeServer.parseLine("attention")
        XCTAssertEqual(ev, .attention(kind: "Stop"))
    }

    func testParsesResume() {
        let ev = BridgeServer.parseLine("resume")
        XCTAssertEqual(ev, .resume)
    }

    func testReturnsNilForUnknown() {
        XCTAssertNil(BridgeServer.parseLine("bogus"))
        XCTAssertNil(BridgeServer.parseLine(""))
    }
}

final class BridgeServerIntegrationTests: XCTestCase {
    func testListenerReceivesEventsFromPoke() throws {
        let sockPath = "/tmp/snapback-bridge-test-\(UUID().uuidString.prefix(8)).sock"
        defer { try? FileManager.default.removeItem(atPath: sockPath) }
        let queue = EventQueue()
        let log = BridgeLog(directory: URL(fileURLWithPath: NSTemporaryDirectory()))
        let server = BridgeServer(socketPath: sockPath, eventQueue: queue, log: log)
        try server.start()
        defer { server.stop() }

        // Wait for the socket to appear.
        for _ in 0..<40 {
            if FileManager.default.fileExists(atPath: sockPath) { break }
            Thread.sleep(forTimeInterval: 0.025)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: sockPath))

        // Write "attention\tPermissionRequest\n" over AF_UNIX using POSIX socket.
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThan(fd, 0)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        _ = sockPath.withCString { ptr -> Void in
            withUnsafeMutableBytes(of: &addr.sun_path) { buf in
                let n = min(strlen(ptr), buf.count - 1)
                buf.baseAddress!.copyMemory(from: UnsafeRawPointer(ptr), byteCount: n)
                buf.baseAddress!.advanced(by: n).assumingMemoryBound(to: CChar.self).pointee = 0
            }
        }
        let connectResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        XCTAssertEqual(connectResult, 0)
        let msg = "attention\tPermissionRequest\n"
        _ = msg.withCString { write(fd, $0, strlen($0)) }
        shutdown(fd, SHUT_WR)
        close(fd)

        // Poll up to 2 s.
        for _ in 0..<80 {
            if queue.depth >= 1 { break }
            Thread.sleep(forTimeInterval: 0.025)
        }
        XCTAssertEqual(queue.depth, 1)
        XCTAssertEqual(queue.pop(), .attention(kind: "PermissionRequest"))
    }
}
