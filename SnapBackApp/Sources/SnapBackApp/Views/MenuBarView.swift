import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSettings = false

    // Claude/Anthropic orange
    static let accentColor = Color(red: 0.878, green: 0.490, blue: 0.310) // #E07D4F

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let err = appState.lastError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

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

            providersSection
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
            appState.checkHooksEnabled()
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
                Slider(value: Binding(
                    get: { appState.volume },
                    set: { appState.setVolume($0) }
                ), in: 0...1)
                .controlSize(.small)
                .tint(Self.accentColor)

                Button(action: { appState.playTestSound() }) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
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

            Picker("", selection: Binding(
                get: { appState.mode },
                set: { appState.setMode($0) }
            )) {
                Text("Both").tag("both")
                Text("Switches Only").tag("switches")
                Text("Sound Only").tag("sound")
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
        }
    }

    // MARK: - Settings

    private var providersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Providers", systemImage: "link.badge.plus")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Toggle(isOn: Binding(
                get: { appState.hookClaude },
                set: { appState.toggleHookClaude($0) }
            )) {
                Text("Claude")
                    .font(.system(size: 11))
            }
            .toggleStyle(.checkbox)

            Toggle(isOn: Binding(
                get: { appState.hookOpenCode },
                set: { appState.toggleHookOpenCode($0) }
            )) {
                Text("OpenCode")
                    .font(.system(size: 11))
            }
            .toggleStyle(.checkbox)
        }
    }

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
                        Picker("", selection: Binding(
                            get: { appState.browser },
                            set: { appState.setBrowser($0) }
                        )) {
                            Text("Chrome").tag("Google Chrome")
                            Text("Safari").tag("Safari")
                            Text("Arc").tag("Arc")
                            Text("Firefox").tag("Firefox")
                            Text("Brave").tag("Brave Browser")
                        }
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(width: 90)
                    }

                    HStack {
                        Text("Throttle")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        Stepper("\(appState.throttleSeconds)s", value: Binding(
                            get: { appState.throttleSeconds },
                            set: { appState.setThrottle($0) }
                        ), in: 1...10)
                        .controlSize(.small)
                    }

                    HStack {
                        Text("Seek back")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        Stepper("\(appState.seekBackSeconds)s", value: Binding(
                            get: { appState.seekBackSeconds },
                            set: { appState.setSeekBack($0) }
                        ), in: 0...5)
                        .controlSize(.small)
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
