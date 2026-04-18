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
    @Published var lastTrigger: Date? = nil
    @Published var runningApps: [String] = []
    @Published var startAtLogin: Bool = false

    private var timer: Timer?

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
            } else if trimmed.hasPrefix("FOCUS_APPS=") {
                focusApps = parseFocusApps(trimmed)
            }
        }
    }

    private func parseConfigLine(_ line: String, key: String) -> String? {
        guard line.hasPrefix("\(key)=") else { return nil }
        var value = String(line.dropFirst(key.count + 1))
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return value
    }

    private func parseFocusApps(_ line: String) -> [String] {
        guard let start = line.firstIndex(of: "("),
              let end = line.lastIndex(of: ")") else { return [] }

        let inner = String(line[line.index(after: start)..<end])
        var apps: [String] = []
        var current = ""
        var inQuotes = false

        for char in inner {
            if char == "\"" {
                if inQuotes && !current.isEmpty {
                    apps.append(current)
                    current = ""
                }
                inQuotes.toggle()
            } else if inQuotes {
                current.append(char)
            }
        }

        return apps
    }

    func saveConfig() {
        // F0b: writer is a no-op until F3 wires mutations through the CLI.
        // Kept callable so callsites compile; the UI controls that would
        // drive it are .disabled(true) at the view layer.
        NSLog("SnapBack: saveConfig() is a no-op until F3")
    }

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
        let command = isEnabled ? "off" : "on"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            ShellCommand.run("snapback \(command)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.checkHooksEnabled()
            }
        }
    }

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

    func updateRunningApps() {
        let workspace = NSWorkspace.shared
        runningApps = workspace.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { $0.localizedName }
            .sorted()
    }

    func addFocusApp(_ app: String) {
        if !focusApps.contains(app) {
            focusApps.append(app)
            saveConfig()
        }
    }

    func removeFocusApp(_ app: String) {
        focusApps.removeAll { $0 == app }
        saveConfig()
    }

    func playTestSound() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let soundPaths = [
                "\(NSHomeDirectory())/.snapback/notification.mp3",
                "/usr/local/share/snapback/notification.mp3",
                "\(NSHomeDirectory())/Documents/Programming/AIAttention/notification.mp3"
            ]

            // Get system volume and multiply with config volume
            let volumeCmd = "sysVol=$(osascript -e 'output volume of (get volume settings)' 2>/dev/null || echo 100); echo \"scale=2; \(self.volume) * $sysVol / 100\" | bc -l"

            for path in soundPaths {
                if FileManager.default.fileExists(atPath: path) {
                    ShellCommand.run("effectiveVol=$(\(volumeCmd)); afplay -v \"$effectiveVol\" '\(path)'")
                    return
                }
            }

            ShellCommand.run("effectiveVol=$(\(volumeCmd)); afplay -v \"$effectiveVol\" /System/Library/Sounds/Ping.aiff")
        }
    }

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
