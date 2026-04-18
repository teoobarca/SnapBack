import XCTest
@testable import SnapBackApp

final class BridgeLogTests: XCTestCase {
    var tmpDir: URL!

    override func setUp() {
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("snapback-log-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testWritesToFile() throws {
        let log = BridgeLog(directory: tmpDir, basename: "bridge.log",
                            maxBytes: 1024, rotations: 2)
        log.info("hello world")
        log.flush()
        let url = tmpDir.appendingPathComponent("bridge.log")
        let contents = try String(contentsOf: url)
        XCTAssertTrue(contents.contains("hello world"))
    }

    func testRotatesAfterMaxBytes() throws {
        let log = BridgeLog(directory: tmpDir, basename: "bridge.log",
                            maxBytes: 100, rotations: 2)
        for i in 0..<50 { log.info("line \(i) with some padding xxxxxxxxxxxxxx") }
        log.flush()
        let base = tmpDir.appendingPathComponent("bridge.log")
        let rotated = tmpDir.appendingPathComponent("bridge.log.1")
        XCTAssertTrue(FileManager.default.fileExists(atPath: base.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: rotated.path))
    }
}
