import SwiftUI

struct FocusAppsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Focus Apps", systemImage: "macwindow.on.rectangle")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            FlowLayout(spacing: 6) {
                ForEach(appState.focusApps, id: \.self) { app in
                    AppChip(name: app) {
                        appState.removeFocusApp(app)
                    }
                }

                Button(action: {
                    appState.updateRunningApps()
                    showingPicker = true
                }) {
                    Label("Add", systemImage: "plus")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(true)
                .popover(isPresented: $showingPicker) {
                    appPicker
                }
            }
        }
    }

    private var appPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Running Apps")
                .font(.system(size: 12, weight: .medium))
                .padding(12)

            Divider()

            if availableApps.isEmpty {
                Text("All apps added")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(availableApps, id: \.self) { app in
                            Button(action: {
                                appState.addFocusApp(app)
                                showingPicker = false
                            }) {
                                HStack(spacing: 8) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: appPath(for: app)))
                                        .resizable()
                                        .frame(width: 18, height: 18)
                                    Text(app)
                                        .font(.system(size: 12))
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .frame(width: 200)
    }

    private var availableApps: [String] {
        appState.runningApps.filter { !appState.focusApps.contains($0) }
    }

    private func appPath(for name: String) -> String {
        for path in ["/Applications/\(name).app", "/System/Applications/\(name).app"] {
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return "/Applications"
    }
}

struct AppChip: View {
    let name: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(name)
                .font(.system(size: 10))
                .lineLimit(1)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.15), in: Capsule())
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, pos) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            lineHeight = max(lineHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + lineHeight), positions)
    }
}
