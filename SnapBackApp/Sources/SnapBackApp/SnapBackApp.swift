import SwiftUI
import AppKit
import Combine
import UserNotifications

@main
struct SnapBackApp: App {
    @StateObject private var appState = AppState()

    // Claude/Anthropic orange
    private let activeColor = Color(red: 0.878, green: 0.490, blue: 0.310)

    init() {
        BridgeRuntime.shared.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(appState.isEnabled ? activeColor : .gray)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - BridgeRuntime

/// Owns the bridge backend (server + peer + orchestrator + browser) for the
/// life of the SnapBack menu-bar app. Single instance, lazily constructed on
/// first access; `start()` must be called from the App's init.
final class BridgeRuntime: ObservableObject {
    static let shared = BridgeRuntime()

    let status = BridgeStatusPublisher()
    @Published var pendingQRURL: String?

    private let tokenStore = KeychainTokenStore()
    private let eventQueue = EventQueue()
    private let log: BridgeLog
    private var bridgeServer: BridgeServer?
    private var peer: MobilePeer?
    private var orchestrator: BridgeOrchestrator?
    private var browser: MDNSBrowser?
    private var cancellables: Set<AnyCancellable> = []
    private var lastNotifiedStatus: BridgeStatus = .unpaired

    init() {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/SnapBack")
        self.log = BridgeLog(directory: dir)
    }

    func start() {
        // Always install the UDS listener so hooks see a socket even before pairing.
        let sockEnv = ProcessInfo.processInfo.environment["SNAPBACK_BRIDGE_SOCKET"]
        let defaultSock = (NSTemporaryDirectory() as NSString).appendingPathComponent("snapback-bridge.sock")
        let sock = sockEnv ?? defaultSock
        let server = BridgeServer(socketPath: sock, eventQueue: eventQueue, log: log)
        do {
            try server.start()
            bridgeServer = server
            log.info("bridge server listening at \(sock)")
        } catch {
            log.error("bridge server start failed: \(error)")
            status.update(.error("UDS listener: \(error)"))
        }

        // If already paired, begin discovery.
        if tokenStore.read() != nil {
            startDiscovery()
        }

        installStatusTransitionNotifier()
    }

    func pair() {
        do {
            // Tear down any existing discovery so re-pair gets a fresh peer/token.
            orchestrator?.stop()
            orchestrator = nil
            peer = nil
            browser?.stop()
            browser = nil

            let token = try tokenStore.generateAndStore()
            let desk = ProcessInfo.processInfo.hostName
            pendingQRURL = Pairing.pairingURL(token: token, deskName: desk)
            startDiscovery()
        } catch {
            status.update(.error("pair: \(error)"))
        }
    }

    func unpair() {
        // Best-effort invalidate BEFORE wiping the token so the signing secret
        // is still valid (Phase 15.3 follow-up).
        if let peer = self.peer {
            let nonce = (0..<16).map { _ in UInt8.random(in: 0...255) }
                                 .map { String(format: "%02x", $0) }.joined()
            let msg = ProtocolMessage(
                version: 1, type: .invalidate,
                timestamp: Int64(Date().timeIntervalSince1970),
                nonceHex: nonce, payload: []
            )
            peer.send(msg)
        }

        // Let the invalidate drain, then tear everything down.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            self.orchestrator?.stop()
            self.orchestrator = nil
            self.peer = nil
            self.browser?.stop()
            self.browser = nil
            try? self.tokenStore.delete()
            DispatchQueue.main.async {
                self.pendingQRURL = nil
                self.status.update(.unpaired)
            }
        }
    }

    // MARK: Private

    private func startDiscovery() {
        guard browser == nil else { return }
        guard let token = tokenStore.read() else { return }
        let browser = MDNSBrowser()
        browser.onDiscover = { [weak self] host, port in
            guard let self else { return }
            if let existingPeer = self.peer {
                // Endpoint changed (e.g. WiFi roam) — tear down stale peer.
                if existingPeer.host != host || existingPeer.port != port {
                    self.log.info("peer endpoint changed to \(host):\(port); reconnecting")
                    self.orchestrator?.stop()
                    self.orchestrator = nil
                    self.peer = nil
                } else {
                    return  // same endpoint, nothing to do
                }
            }
            let deskName = ProcessInfo.processInfo.hostName
            let peer = MobilePeer(host: host, port: port, secret: token, peerName: deskName)
            let orch = BridgeOrchestrator(
                eventQueue: self.eventQueue,
                peer: peer,
                status: self.status
            )
            orch.start()
            self.peer = peer
            self.orchestrator = orch
            self.log.info("bridge connected peer at \(host):\(port)")
        }
        browser.onDisappear = { [weak self] in
            guard let self else { return }
            self.log.info("peer disappeared from mDNS; tearing down")
            self.orchestrator?.stop()
            self.orchestrator = nil
            self.peer = nil
        }
        browser.start()
        self.browser = browser
    }

    // Phase 15.4: macOS notifications on real state transitions.
    private func installStatusTransitionNotifier() {
        status.$current
            .dropFirst()
            .sink { [weak self] newStatus in
                guard let self else { return }
                let last = self.lastNotifiedStatus
                defer { self.lastNotifiedStatus = newStatus }
                guard last != newStatus else { return }
                switch (last, newStatus) {
                case (.connected, .unreachable), (.connected, .error):
                    BridgeRuntime.notify(title: "SnapBack", body: "Mobile unreachable")
                case (_, .connected) where last != .connecting:
                    BridgeRuntime.notify(title: "SnapBack", body: "Mobile reconnected")
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    private static func notify(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(req, withCompletionHandler: nil)
    }
}
