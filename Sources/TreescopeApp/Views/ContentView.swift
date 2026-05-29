import SwiftUI
import TreescopeViewerCore

struct ContentView: View {
    @EnvironmentObject var session: InspectorSession

    @State private var showWireframe = true
    @State private var showSnapshots = true
    @State private var exploded = false
    @State private var zoom: Double = 1.0

    var body: some View {
        Group {
            if session.isConnected {
                workspace
            } else {
                ConnectionView()
            }
        }
        .animation(.default, value: session.isConnected)
    }

    private var workspace: some View {
        NavigationSplitView {
            TreeSidebar()
                .navigationSplitViewColumnWidth(min: 240, ideal: 320, max: 480)
        } content: {
            CanvasView(showWireframe: $showWireframe,
                       showSnapshots: $showSnapshots,
                       exploded: $exploded,
                       zoom: $zoom)
                .navigationSplitViewColumnWidth(min: 360, ideal: 560)
        } detail: {
            InspectorPanel()
                .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 520)
        }
        .toolbar { toolbarContent }
        .navigationTitle(session.serverInfo?.device.appName ?? "Treescope")
        #if os(macOS)
        .navigationSubtitle(deviceSubtitle)
        #endif
    }

    private var deviceSubtitle: String {
        guard let d = session.serverInfo?.device else { return "" }
        return "\(d.osName) \(d.osVersion) · \(d.deviceModel)"
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                Task { await session.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(session.isRefreshing)
            .help("Recapture the hierarchy (⌘R)")

            Toggle(isOn: $showWireframe) {
                Label("Wireframe", systemImage: "grid")
            }
            .help("Show frame outlines")

            Toggle(isOn: $showSnapshots) {
                Label("Snapshots", systemImage: "photo")
            }
            .help("Show rendered view snapshots")

            Toggle(isOn: $exploded) {
                Label("3D", systemImage: "cube")
            }
            .help("Exploded 3D layer view")

            Spacer()

            if session.isRefreshing {
                ProgressView().controlSize(.small)
            }

            Text(nodeCountLabel)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(role: .destructive) {
                session.disconnect()
            } label: {
                Label("Disconnect", systemImage: "bolt.horizontal.circle")
            }
            .help("Disconnect from \(session.endpointLabel)")
        }
    }

    private var nodeCountLabel: String {
        guard let snapshot = session.snapshot else { return "" }
        return "\(snapshot.totalNodeCount) nodes"
    }
}
