import SwiftUI
import TreescopeViewerCore

@main
struct TreescopeApp: App {
    @StateObject private var session = InspectorSession()
    @StateObject private var browser = ServiceBrowser()

    var body: some Scene {
        WindowGroup("Treescope") {
            ContentView()
                .environmentObject(session)
                .environmentObject(browser)
                .frame(minWidth: 960, minHeight: 600)
        }
        #if os(macOS)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Refresh Hierarchy") {
                    Task { await session.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!session.isConnected)
            }
        }
        #endif
    }
}
