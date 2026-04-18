import Foundation

// MARK: - BridgeServer (parser only — Task 10.1)

/// Translates TSV-ish lines written by `snapback-poke` into `BridgeEvent`s.
public final class BridgeServer {

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
}
