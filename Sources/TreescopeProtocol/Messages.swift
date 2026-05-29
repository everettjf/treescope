import Foundation

/// Options controlling a hierarchy capture request.
public struct HierarchyOptions: Codable, Hashable, Sendable {
    /// Include reflected SwiftUI subtrees discovered under hosting views.
    public var includeSwiftUI: Bool
    /// Include CALayer children of platform views.
    public var includeLayers: Bool
    /// Skip Apple-internal/system views (keyboard, status bar internals…).
    public var hideSystemViews: Bool
    /// Eagerly attach a small snapshot id to every visible node.
    public var requestSnapshots: Bool
    /// Maximum traversal depth (0 = unlimited).
    public var maxDepth: Int

    public init(includeSwiftUI: Bool = true,
                includeLayers: Bool = false,
                hideSystemViews: Bool = false,
                requestSnapshots: Bool = true,
                maxDepth: Int = 0) {
        self.includeSwiftUI = includeSwiftUI
        self.includeLayers = includeLayers
        self.hideSystemViews = hideSystemViews
        self.requestSnapshots = requestSnapshots
        self.maxDepth = maxDepth
    }

    public static let `default` = HierarchyOptions()
}

/// Messages sent from the viewer (client) to the in-app server.
public enum ClientMessage: Codable, Sendable {
    case handshake(ClientInfo)
    case fetchHierarchy(HierarchyOptions)
    case fetchSnapshot(nodeID: String, scale: Double)
    case setAttribute(nodeID: String, keyPath: String, value: AttributeValue)
    case highlight(nodeID: String?)
    case ping
}

/// Messages sent from the in-app server to the viewer (client).
public enum ServerMessage: Codable, Sendable {
    case handshakeAck(ServerInfo)
    case hierarchy(HierarchySnapshot)
    case snapshot(SnapshotImage)
    case attributeResult(nodeID: String, keyPath: String, success: Bool, message: String?)
    case event(ServerEvent)
    case error(code: Int, message: String)
    case pong
}

/// Unsolicited server-side events (id == 0 on the wire).
public enum ServerEvent: Codable, Sendable {
    case hierarchyChanged
    case willDisconnect(reason: String)
    case log(String)
}

/// Correlatable client request. `id` ties a response back to its request.
public struct ClientEnvelope: Codable, Sendable {
    public var id: UInt64
    public var message: ClientMessage
    public init(id: UInt64, message: ClientMessage) {
        self.id = id
        self.message = message
    }
}

/// Correlatable server response. `id` matches the originating request, or 0 for pushes.
public struct ServerEnvelope: Codable, Sendable {
    public var id: UInt64
    public var message: ServerMessage
    public init(id: UInt64, message: ServerMessage) {
        self.id = id
        self.message = message
    }

    public static func push(_ message: ServerMessage) -> ServerEnvelope {
        ServerEnvelope(id: 0, message: message)
    }
}
