import SwiftUI
import AppKit

struct MobileTabView: View {
    @ObservedObject var status: BridgeStatusPublisher
    var onPair: () -> Void
    var onUnpair: () -> Void
    var qrImage: CGImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Mobile")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                statusDot
                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            if let qr = qrImage {
                let nsImage = NSImage(cgImage: qr, size: NSSize(width: 180, height: 180))
                Image(nsImage: nsImage)
                    .interpolation(.none)
                    .frame(width: 180, height: 180)
                    .padding(8)
                    .background(Color.white)
                    .cornerRadius(8)
                Text("Scan with SnapBack Mobile to pair.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Button("Cancel", action: onUnpair)
                    .controlSize(.small)
            } else {
                switch status.current {
                case .unpaired:
                    Button("Pair mobile…", action: onPair)
                        .controlSize(.small)
                case .connected:
                    Text("Paired & connected.")
                        .font(.system(size: 11))
                    Button("Unpair", role: .destructive, action: onUnpair)
                        .controlSize(.small)
                case .connecting:
                    Text("Connecting to phone…")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                case .unreachable:
                    Text("Paired — phone unreachable.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Button("Unpair", role: .destructive, action: onUnpair)
                        .controlSize(.small)
                case .error(let msg):
                    Text("Error: \(msg)")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                    Button("Retry pair", action: onPair)
                        .controlSize(.small)
                }
            }
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
    }

    private var statusColor: Color {
        switch status.current {
        case .connected: return .green
        case .connecting, .unreachable: return .yellow
        case .error: return .red
        case .unpaired: return .gray
        }
    }

    private var statusText: String {
        switch status.current {
        case .connected: return "connected"
        case .connecting: return "connecting…"
        case .unreachable: return "unreachable"
        case .error: return "error"
        case .unpaired: return "unpaired"
        }
    }
}
