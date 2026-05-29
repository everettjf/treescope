import Foundation
import Combine
import Network
import TreescopeProtocol

/// Observable, main-actor session model that drives the viewer UI: owns the
/// connection, the current hierarchy snapshot, selection, and image/edit calls.
@MainActor
public final class InspectorSession: ObservableObject {

    public enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    @Published public private(set) var connectionState: ConnectionState = .disconnected
    @Published public private(set) var serverInfo: ServerInfo?
    @Published public private(set) var snapshot: HierarchySnapshot?
    @Published public private(set) var snapshotImages: [String: SnapshotImage] = [:]
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var lastError: String?

    @Published public var selectedNodeID: String?
    @Published public var expandedNodeIDs: Set<String> = []

    // Display options.
    @Published public var hideSystemViews = false { didSet { objectWillChange.send() } }
    @Published public var searchText = ""

    private let client = TransportClient()
    private var endpointDescription = ""

    public init() {
        client.onStateChange = { [weak self] state in
            DispatchQueue.main.async { self?.applyTransportState(state) }
        }
        client.onEvent = { [weak self] event in
            DispatchQueue.main.async { self?.handleEvent(event) }
        }
    }

    public var isConnected: Bool { connectionState == .connected }

    public var selectedNode: ViewNode? {
        guard let id = selectedNodeID else { return nil }
        return snapshot?.node(withID: id)
    }

    /// Roots filtered by the current search/hide options, preserving ancestors
    /// of any matching node.
    public var displayRoots: [ViewNode] {
        guard let roots = snapshot?.roots else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return roots.compactMap { filter(node: $0, query: query) }
    }

    // MARK: Connection

    public func connect(host: String, port: UInt16) async {
        endpointDescription = "\(host):\(port)"
        connectionState = .connecting
        lastError = nil
        do {
            try await client.connect(host: host, port: port)
            try await handshakeAndLoad()
        } catch {
            connectionState = .failed(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    public func connect(to endpoint: NWEndpoint, name: String) async {
        endpointDescription = name
        connectionState = .connecting
        lastError = nil
        do {
            try await client.connect(to: endpoint)
            try await handshakeAndLoad()
        } catch {
            connectionState = .failed(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    private func handshakeAndLoad() async throws {
        let info = try await client.handshake()
        serverInfo = info
        connectionState = .connected
        await refresh()
    }

    public func disconnect() {
        client.disconnect()
        connectionState = .disconnected
        snapshot = nil
        serverInfo = nil
        snapshotImages = [:]
        selectedNodeID = nil
    }

    public var endpointLabel: String { endpointDescription }

    // MARK: Data

    public func refresh() async {
        guard isConnected else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let options = HierarchyOptions(includeSwiftUI: true,
                                           includeLayers: false,
                                           hideSystemViews: false,
                                           requestSnapshots: true)
            let snap = try await client.fetchHierarchy(options: options)
            snapshot = snap
            snapshotImages = [:]
            // Auto-expand the first couple of levels for orientation.
            expandedNodeIDs = autoExpand(roots: snap.roots, levels: 3)
            if selectedNodeID == nil { selectedNodeID = snap.roots.first?.id }
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func loadSnapshotImage(for nodeID: String) async {
        guard isConnected, snapshotImages[nodeID] == nil else { return }
        do {
            if let image = try await client.fetchSnapshot(nodeID: nodeID, scale: 2) {
                snapshotImages[nodeID] = image
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    @discardableResult
    public func setAttribute(nodeID: String, keyPath: String, value: AttributeValue) async -> Bool {
        guard isConnected else { return false }
        do {
            let ok = try await client.setAttribute(nodeID: nodeID, keyPath: keyPath, value: value)
            if ok { await refresh() }
            return ok
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    public func highlightOnDevice(nodeID: String?) async {
        guard isConnected else { return }
        _ = try? await client.send(.highlight(nodeID: nodeID))
    }

    // MARK: Helpers

    private func applyTransportState(_ state: TransportClient.State) {
        switch state {
        case .failed(let m):
            connectionState = .failed(m)
            lastError = m
        case .cancelled:
            if connectionState == .connected { connectionState = .disconnected }
        default:
            break
        }
    }

    private func handleEvent(_ event: ServerEvent) {
        switch event {
        case .hierarchyChanged:
            Task { await refresh() }
        case .willDisconnect:
            disconnect()
        case .log:
            break
        }
    }

    private func autoExpand(roots: [ViewNode], levels: Int) -> Set<String> {
        var ids: Set<String> = []
        func walk(_ node: ViewNode, depth: Int) {
            guard depth < levels else { return }
            if !node.children.isEmpty { ids.insert(node.id) }
            for child in node.children { walk(child, depth: depth + 1) }
        }
        roots.forEach { walk($0, depth: 0) }
        return ids
    }

    /// Test seam: inject a snapshot without a live connection.
    func ingestSnapshotForTesting(_ snapshot: HierarchySnapshot) {
        self.snapshot = snapshot
        self.connectionState = .connected
    }

    private func filter(node: ViewNode, query: String) -> ViewNode? {
        if hideSystemViews, node.flags.contains(.systemView), !node.flags.contains(.hostsSwiftUI) {
            return nil
        }
        let filteredChildren = node.children.compactMap { filter(node: $0, query: query) }
        let selfMatches = query.isEmpty || matches(node, query: query)
        if selfMatches || !filteredChildren.isEmpty {
            var copy = node
            copy.children = filteredChildren
            return copy
        }
        return nil
    }

    private func matches(_ node: ViewNode, query: String) -> Bool {
        if query.isEmpty { return true }
        if node.displayName.lowercased().contains(query) { return true }
        if node.className.lowercased().contains(query) { return true }
        if let label = node.label?.lowercased(), label.contains(query) { return true }
        return false
    }
}
