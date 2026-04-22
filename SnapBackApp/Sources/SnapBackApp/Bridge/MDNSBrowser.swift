import Foundation
import Network

/// Discovers `_snapback._tcp.local` peers via NWBrowser.
///
/// Re-arms the browser whenever the network path changes (Wi-Fi switch,
/// docking, etc.), so reconnection after a roam is automatic.
///
/// Note: NWPathMonitor fires its pathUpdateHandler once immediately with the
/// current path, causing a redundant browser restart at init — harmless but
/// expected.
public final class MDNSBrowser {
    /// Fires when a peer is discovered or its resolved address changes.
    public var onDiscover: ((String, UInt16) -> Void)?
    /// Fires when all previously-discovered services disappear.
    public var onDisappear: (() -> Void)?

    private var browser: NWBrowser?
    private var pathMonitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "com.snapback.bridge.mdns")
    private var stopped = true
    private var pendingResolutions: [NWConnection] = []
    /// Last resolved endpoint so we can detect address changes.
    private var lastResolvedHost: String?
    private var lastResolvedPort: UInt16?
    /// Number of services in the most recent browse result.
    private var lastResultCount = 0

    public init() {}

    public func start() {
        stopped = false
        startBrowser()
        let pm = NWPathMonitor()
        pm.pathUpdateHandler = { [weak self] _ in
            self?.queue.async {
                guard let self, !self.stopped else { return }
                self.browser?.cancel()
                self.startBrowser()
            }
        }
        pm.start(queue: queue)
        pathMonitor = pm
    }

    public func stop() {
        stopped = true
        browser?.cancel()
        browser = nil
        pathMonitor?.cancel()
        pathMonitor = nil
        for conn in pendingResolutions { conn.cancel() }
        pendingResolutions.removeAll()
        lastResolvedHost = nil
        lastResolvedPort = nil
        lastResultCount = 0
    }

    private func startBrowser() {
        guard !stopped else { return }
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_snapback._tcp", domain: "local.")
        let b = NWBrowser(for: descriptor, using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            if results.isEmpty && self.lastResultCount > 0 {
                self.lastResolvedHost = nil
                self.lastResolvedPort = nil
                self.lastResultCount = 0
                self.onDisappear?()
            } else {
                self.lastResultCount = results.count
                for r in results {
                    self.resolve(endpoint: r.endpoint)
                }
            }
        }
        b.start(queue: queue)
        browser = b
    }

    private func resolve(endpoint: NWEndpoint) {
        let conn = NWConnection(to: endpoint, using: .tcp)
        pendingResolutions.append(conn)
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if case let .hostPort(host, port) = conn.currentPath?.remoteEndpoint {
                    let hostString: String
                    switch host {
                    case .name(let s, _): hostString = s
                    case .ipv4(let ipv4):  hostString = "\(ipv4)"
                    case .ipv6(let ipv6):  hostString = "\(ipv6)"
                    @unknown default:       hostString = "unknown"
                    }
                    guard let self else { return }
                    // Fire onDiscover on first resolution or when address changes.
                    if self.lastResolvedHost != hostString || self.lastResolvedPort != port.rawValue {
                        self.lastResolvedHost = hostString
                        self.lastResolvedPort = port.rawValue
                        self.onDiscover?(hostString, port.rawValue)
                    }
                }
                conn.cancel()
            case .failed, .cancelled:
                self?.pendingResolutions.removeAll { $0 === conn }
            default:
                break
            }
        }
        conn.start(queue: queue)
    }
}
