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
    public var onDiscover: ((String, UInt16) -> Void)?

    private var browser: NWBrowser?
    private var pathMonitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "com.snapback.bridge.mdns")

    public init() {}

    public func start() {
        startBrowser()
        let pm = NWPathMonitor()
        pm.pathUpdateHandler = { [weak self] _ in
            self?.queue.async {
                self?.browser?.cancel()
                self?.startBrowser()
            }
        }
        pm.start(queue: queue)
        pathMonitor = pm
    }

    public func stop() {
        browser?.cancel()
        browser = nil
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    private func startBrowser() {
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_snapback._tcp", domain: "local.")
        let b = NWBrowser(for: descriptor, using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            for r in results {
                self?.resolve(endpoint: r.endpoint)
            }
        }
        b.start(queue: queue)
        browser = b
    }

    private func resolve(endpoint: NWEndpoint) {
        let conn = NWConnection(to: endpoint, using: .tcp)
        conn.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                if case let .hostPort(host, port) = conn.currentPath?.remoteEndpoint {
                    let hostString: String
                    switch host {
                    case .name(let s, _): hostString = s
                    case .ipv4(let ipv4):  hostString = "\(ipv4)"
                    case .ipv6(let ipv6):  hostString = "\(ipv6)"
                    @unknown default:       hostString = "unknown"
                    }
                    self?.onDiscover?(hostString, port.rawValue)
                }
                conn.cancel()
            } else if case .failed = state {
                conn.cancel()
            }
        }
        conn.start(queue: queue)
    }
}
