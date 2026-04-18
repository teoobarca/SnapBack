import Foundation

struct ShellResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

struct ShellCommand {
    /// Explicit argv execution — no shell parsing. Used for all writes.
    @discardableResult
    static func run(executable: String, args: [String]) -> ShellResult {
        let process = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.standardOutput = outPipe
        process.standardError = errPipe

        var env = ProcessInfo.processInfo.environment
        let existingPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        // Prepend common user-install locations that are missing from LaunchAgent PATH.
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(NSHomeDirectory())/.local/bin:\(existingPath)"
        process.environment = env

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ShellResult(stdout: "", stderr: "spawn failed: \(error)", exitCode: -1)
        }

        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return ShellResult(stdout: out, stderr: err, exitCode: process.terminationStatus)
    }

    /// Legacy shell pipeline runner.  Keep ONLY for on/off flows; do not
    /// pass user-controlled strings here.
    @discardableResult
    static func runShell(_ command: String) -> String {
        let result = run(executable: "/bin/bash", args: ["-c", command])
        return result.stdout
    }
}
