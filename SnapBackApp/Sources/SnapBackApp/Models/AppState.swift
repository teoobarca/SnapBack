import SwiftUI
import Combine
import ServiceManagement

class AppState: ObservableObject {
    @Published var isEnabled: Bool = false
    @Published var mode: String = "full"
    @Published var volume: Double = 1.0
    @Published var focusApps: [String] = []
    @Published var browser: String = "Google Chrome"
    @Published var throttleSeconds: Int = 2
    @Published var seekBackSeconds: Int = 1
    @Published var focusDelay: Double = 0.5
    @Published var notificationSound: String = "default"
    @Published var lastTrigger: Date? = nil
    @Published var runningApps: [String] = []
    @Published var startAtLogin: Bool = false
    @Published var lastError: String? = nil

    let cli = SnapBackCLI()

    /// Timestamp of the last outgoing write — used by ConfigWatcher to suppress echo.
    private(set) var lastOutgoingWriteAt: Date? = nil

    private var debouncers: [String: DispatchWorkItem] = [:]
    private let debounceQueue = DispatchQueue(label: "com.snapback.debounce")

    private var timer: Timer?
    private var watcher: ConfigWatcher?

    private var configPath: String {
        let xdgConfig = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] ?? "\(NSHomeDirectory())/.config"
        return "\(xdgConfig)/snapback/config"
    }

    private var claudeSettingsPath: String {
        "\(NSHomeDirectory())/.claude/settings.json"
    }

    init() {
        loadConfig()
        checkHooksEnabled()
        checkLoginItemStatus()
        watcher = ConfigWatcher(
            path: configPath,
            onChange: { [weak self] in
                DispatchQueue.main.async { self?.loadConfig() }
            },
            lastOwnWriteAt: { [weak self] in self?.lastOutgoingWriteAt }
        )
    }

    deinit {
        timer?.invalidate()
    }

    func loadConfig() {
        guard let content = try? String(contentsOfFile: configPath, encoding: .utf8) else { return }

        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") || trimmed.isEmpty { continue }

            if let match = parseConfigLine(trimmed, key: "MODE") {
                mode = match
            } else if let match = parseConfigLine(trimmed, key: "VOLUME") {
                volume = Double(match) ?? 1.0
            } else if let match = parseConfigLine(trimmed, key: "BROWSER") {
                browser = match
            } else if let match = parseConfigLine(trimmed, key: "THROTTLE_SECONDS") {
                throttleSeconds = Int(match) ?? 2
            } else if let match = parseConfigLine(trimmed, key: "SEEK_BACK_SECONDS") {
                seekBackSeconds = Int(match) ?? 1
            } else if let match = parseConfigLine(trimmed, key: "FOCUS_DELAY") {
                focusDelay = Double(match) ?? 0.5
            } else if let match = parseConfigLine(trimmed, key: "NOTIFICATION_SOUND") {
                notificationSound = match
            } else if trimmed.hasPrefix("FOCUS_APPS=") {
                focusApps = parseFocusApps(trimmed)
            }
        }
    }

    private func parseConfigLine(_ line: String, key: String) -> String? {
        guard line.hasPrefix("\(key)=") else { return nil }
        var value = String(line.dropFirst(key.count + 1))
        // Strip at most one pair of surrounding double quotes.
        if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        // Unescape the four bytes we escape on write: \\ \$ \` \"
        var out = ""
        var i = value.startIndex
        while i < value.endIndex {
            let c = value[i]
            if c == "\\" {
                let next = value.index(after: i)
                if next < value.endIndex {
                    let n = value[next]
                    if n == "\\" || n == "$" || n == "`" || n == "\"" {
                        out.append(n)
                        i = value.index(after: next)
                        continue
                    }
                }
            }
            out.append(c)
            i = value.index(after: i)
        }
        return out
    }

    private func parseFocusApps(_ line: String) -> [String] {
        guard let start = line.firstIndex(of: "("),
              let end = line.lastIndex(of: ")") else { return [] }
        let inner = String(line[line.index(after: start)..<end])

        var apps: [String] = []
        var current = ""
        var inQuotes = false
        var escaped = false

        for char in inner {
            if escaped {
                current.append(char)
                escaped = false
                continue
            }
            if char == "\\" && inQuotes {
                escaped = true
                continue
            }
            if char == "\"" {
                if inQuotes {
                    apps.append(current)
                    current = ""
                }
                inQuotes.toggle()
                continue
            }
            if inQuotes {
                current.append(char)
            }
        }
        return apps
    }

    // MARK: - Write helpers

    private func writeResult(_ result: ShellResult?, label: String) {
        guard let result else {
            DispatchQueue.main.async { self.lastError = "SnapBack CLI not found" }
            return
        }
        if result.exitCode != 0 {
            let msg = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async { self.lastError = "\(label): \(msg.isEmpty ? "exit \(result.exitCode)" : msg)" }
        } else {
            DispatchQueue.main.async { self.lastError = nil }
        }
    }

    private func debounced(_ key: String, _ action: @escaping () -> Void) {
        debounceQueue.async { [weak self] in
            self?.debouncers[key]?.cancel()
            let item = DispatchWorkItem(block: action)
            self?.debouncers[key] = item
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.2, execute: item)
        }
    }

    // MARK: - Per-key setters

    func setVolume(_ v: Double) {
        volume = v
        debounced("volume") { [weak self] in
            guard let self else { return }
            self.lastOutgoingWriteAt = Date()  // mark BEFORE the write
            self.writeResult(self.cli.setVolume(v), label: "volume")
        }
    }

    func setMode(_ m: String) {
        mode = m
        debounced("mode") { [weak self] in
            guard let self else { return }
            self.lastOutgoingWriteAt = Date()  // mark BEFORE the write
            self.writeResult(self.cli.setMode(m), label: "mode")
        }
    }

    func setBrowser(_ b: String) {
        browser = b
        debounced("browser") { [weak self] in
            guard let self else { return }
            self.lastOutgoingWriteAt = Date()  // mark BEFORE the write
            self.writeResult(self.cli.setBrowser(b), label: "browser")
        }
    }

    func setFocusApps(_ apps: [String]) {
        focusApps = apps
        debounced("focus") { [weak self] in
            guard let self else { return }
            self.lastOutgoingWriteAt = Date()  // mark BEFORE the write
            self.writeResult(self.cli.setFocusApps(apps), label: "focus")
        }
    }

    func setThrottle(_ s: Int) {
        throttleSeconds = s
        debounced("throttle") { [weak self] in
            guard let self else { return }
            self.lastOutgoingWriteAt = Date()  // mark BEFORE the write
            self.writeResult(self.cli.setThrottle(s), label: "throttle")
        }
    }

    func setSeekBack(_ s: Int) {
        seekBackSeconds = s
        debounced("seekBack") { [weak self] in
            guard let self else { return }
            self.lastOutgoingWriteAt = Date()  // mark BEFORE the write
            self.writeResult(self.cli.setSeekBack(s), label: "seekBack")
        }
    }

    // MARK: - Focus app management

    func addFocusApp(_ app: String) {
        if !focusApps.contains(app) {
            setFocusApps(focusApps + [app])
        }
    }

    func removeFocusApp(_ app: String) {
        setFocusApps(focusApps.filter { $0 != app })
    }

    func moveFocusApp(_ app: String, by offset: Int) {
        guard let idx = focusApps.firstIndex(of: app) else { return }
        let newIdx = max(0, min(focusApps.count - 1, idx + offset))
        guard newIdx != idx else { return }
        var arr = focusApps
        arr.remove(at: idx)
        arr.insert(app, at: newIdx)
        setFocusApps(arr)
    }

    // MARK: - Hooks / enabled state

    func checkHooksEnabled() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard let content = try? String(contentsOfFile: self.claudeSettingsPath, encoding: .utf8) else {
                DispatchQueue.main.async {
                    self.isEnabled = false
                }
                return
            }
            let enabled = content.contains("snapback.sh")
            DispatchQueue.main.async {
                self.isEnabled = enabled
            }
        }
    }

    func toggleEnabled() {
        let wasEnabled = isEnabled
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let result = wasEnabled ? self.cli.off() : self.cli.on()
            DispatchQueue.main.async {
                if result == nil { self.lastError = "SnapBack CLI not found" }
                else if result!.exitCode != 0 {
                    self.lastError = "toggle: exit \(result!.exitCode)"
                }
                self.checkHooksEnabled()
            }
        }
    }

    // MARK: - Login item

    func checkLoginItemStatus() {
        startAtLogin = SMAppService.mainApp.status == .enabled
    }

    func toggleLoginItem() {
        do {
            if startAtLogin {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            // Silently handle - status will be refreshed
        }
        checkLoginItemStatus()
    }

    // MARK: - Running apps

    func updateRunningApps() {
        let workspace = NSWorkspace.shared
        runningApps = workspace.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { $0.localizedName }
            .sorted()
    }

    // MARK: - Test sound

    func playTestSound() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.writeResult(self.cli.test(), label: "test")
        }
    }

    // MARK: - Last trigger

    func refreshLastTrigger() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let tmpDir = ProcessInfo.processInfo.environment["TMPDIR"] ?? "/tmp"
            let lastFile = "\(tmpDir)/snapback_last"

            guard let attributes = try? FileManager.default.attributesOfItem(atPath: lastFile),
                  let modDate = attributes[.modificationDate] as? Date else {
                return
            }

            DispatchQueue.main.async {
                self?.lastTrigger = modDate
            }
        }
    }
}
