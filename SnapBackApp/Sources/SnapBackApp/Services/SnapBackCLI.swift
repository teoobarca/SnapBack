import Foundation

final class SnapBackCLI {
    /// Absolute path to the `snapback` executable, or nil if not found.
    let executablePath: String?

    init() {
        self.executablePath = Self.resolve()
    }

    private static func resolve() -> String? {
        // 1. Info.plist override (set by build-app.sh at build time).
        if let override = Bundle.main.object(forInfoDictionaryKey: "SnapBackCLIPath") as? String,
           FileManager.default.isExecutableFile(atPath: override) {
            return override
        }
        // 2. Hardcoded candidate list.
        let candidates = [
            "/usr/local/bin/snapback",
            "/opt/homebrew/bin/snapback",
            "\(NSHomeDirectory())/.local/bin/snapback",
            "\(NSHomeDirectory())/.snapback/snapback",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                // realpath-style resolution
                if let resolved = try? FileManager.default.destinationOfSymbolicLink(atPath: path) {
                    // If relative, resolve against the symlink directory
                    if resolved.hasPrefix("/") { return resolved }
                    let dir = (path as NSString).deletingLastPathComponent
                    return (dir as NSString).appendingPathComponent(resolved)
                }
                return path
            }
        }
        return nil
    }

    /// Execute `snapback` with the given args.  Returns nil if the CLI is not found.
    @discardableResult
    func run(_ args: [String]) -> ShellResult? {
        guard let path = executablePath else { return nil }
        return ShellCommand.run(executable: path, args: args)
    }

    // Typed wrappers — one per mutation.
    func setVolume(_ v: Double) -> ShellResult? { run(["volume", String(format: "%.2f", v)]) }
    func setMode(_ m: String) -> ShellResult? { run(["mode", m]) }
    func setBrowser(_ b: String) -> ShellResult? { run(["browser", b]) }
    func setFocusApps(_ apps: [String]) -> ShellResult? { run(["focus", "set"] + apps) }
    func setThrottle(_ s: Int) -> ShellResult? { run(["config", "set", "THROTTLE_SECONDS", String(s)]) }
    func setSeekBack(_ s: Int) -> ShellResult? { run(["config", "set", "SEEK_BACK_SECONDS", String(s)]) }
    func test() -> ShellResult? { run(["test"]) }
    func on() -> ShellResult? { run(["on"]) }
    func off() -> ShellResult? { run(["off"]) }
}
