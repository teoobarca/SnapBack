import SwiftUI
import AppKit

@main
struct SnapBackApp: App {
    @StateObject private var appState = AppState()

    // Claude/Anthropic orange
    private let activeColor = Color(red: 0.878, green: 0.490, blue: 0.310)

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
