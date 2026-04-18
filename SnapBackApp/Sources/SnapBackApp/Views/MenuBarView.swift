import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSettings = false

    // Claude/Anthropic orange
    static let accentColor = Color(red: 0.878, green: 0.490, blue: 0.310) // #E07D4F

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

            Divider().opacity(0.3)

            volumeSection
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider().opacity(0.3)

            modeSection
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider().opacity(0.3)

            FocusAppsView()
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider().opacity(0.3)

            settingsSection
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider().opacity(0.3)

            footerSection
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(width: 280)
        .onAppear {
            appState.refreshLastTrigger()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(appState.isEnabled ? Self.accentColor : Color.gray.opacity(0.4))
                .frame(width: 8, height: 8)

            Text("SnapBack")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            Toggle("", isOn: Binding(
                get: { appState.isEnabled },
                set: { _ in appState.toggleEnabled() }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
        }
    }

    // MARK: - Volume

    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Volume", systemImage: volumeIcon)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int(appState.volume * 100))%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                Slider(value: $appState.volume, in: 0...1)
                    .controlSize(.small)
                    .tint(Self.accentColor)
                    .onChange(of: appState.volume) { _ in
                        appState.saveConfig()
                    }
                    .disabled(true)

                Button(action: { appState.playTestSound() }) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .disabled(true)
            }
        }
    }

    private var volumeIcon: String {
        if appState.volume == 0 { return "speaker.slash.fill" }
        if appState.volume < 0.33 { return "speaker.wave.1.fill" }
        if appState.volume < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    // MARK: - Mode

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Mode", systemImage: "slider.horizontal.3")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Picker("", selection: $appState.mode) {
                Text("Full").tag("full")
                Text("Sound Only").tag("sound")
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .onChange(of: appState.mode) { _ in
                appState.saveConfig()
            }
            .disabled(true)
        }
    }

    // MARK: - Settings

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.easeOut(duration: 0.15)) {
                    showSettings.toggle()
                }
            }) {
                HStack {
                    Label("Settings", systemImage: "gearshape")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.6))
                        .rotationEffect(.degrees(showSettings ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if showSettings {
                VStack(spacing: 10) {
                    HStack {
                        Text("Browser")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        Picker("", selection: $appState.browser) {
                            Text("Chrome").tag("Google Chrome")
                            Text("Safari").tag("Safari")
                            Text("Arc").tag("Arc")
                            Text("Firefox").tag("Firefox")
                            Text("Brave").tag("Brave Browser")
                        }
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(width: 90)
                        .onChange(of: appState.browser) { _ in
                            appState.saveConfig()
                        }
                        .disabled(true)
                    }

                    HStack {
                        Text("Throttle")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        Stepper("\(appState.throttleSeconds)s", value: $appState.throttleSeconds, in: 1...10)
                            .controlSize(.small)
                            .onChange(of: appState.throttleSeconds) { _ in
                                appState.saveConfig()
                            }
                            .disabled(true)
                    }

                    HStack {
                        Text("Seek back")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        Stepper("\(appState.seekBackSeconds)s", value: $appState.seekBackSeconds, in: 0...5)
                            .controlSize(.small)
                            .onChange(of: appState.seekBackSeconds) { _ in
                                appState.saveConfig()
                            }
                            .disabled(true)
                    }
                }
                .padding(.top, 10)
            }
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 8) {
            HStack {
                Toggle(isOn: Binding(
                    get: { appState.startAtLogin },
                    set: { _ in appState.toggleLoginItem() }
                )) {
                    Text("Start at Login")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
            }

            HStack {
                if let lastTrigger = appState.lastTrigger {
                    Text(timeAgo(lastTrigger))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.7))
                } else {
                    Text("No triggers yet")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.7))
                }

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            }
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }
}
