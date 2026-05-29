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
public enum ClientMessage: Sendable {
    case handshake(ClientInfo)
    case fetchHierarchy(HierarchyOptions)
    case fetchSnapshot(nodeID: String, scale: Double)
    case setAttribute(nodeID: String, keyPath: String, value: AttributeValue)
    case highlight(nodeID: String?)
    case ping
}

/// Messages sent from the in-app server to the viewer (client).
public enum ServerMessage: Sendable {
    case handshakeAck(ServerInfo)
    case hierarchy(HierarchySnapshot)
    case snapshot(SnapshotImage)
    case attributeResult(nodeID: String, keyPath: String, success: Bool, message: String?)
    case event(ServerEvent)
    case error(code: Int, message: String)
    case pong
}

/// Unsolicited server-side events (id == 0 on the wire).
public enum ServerEvent: Sendable {
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

// MARK: - Stable wire encoding
//
// All three message enums use a `"t"` discriminator with flat sibling fields,
// matching `Web/src/protocol.ts` on the viewer side. This keeps the browser
// client free of Swift's synthesized `{"case": {"_0": ...}}` shape.

extension ClientMessage: Codable {
    private enum CodingKeys: String, CodingKey { case t, client, options, nodeID, scale, keyPath, value }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .handshake(let info):
            try c.encode("handshake", forKey: .t); try c.encode(info, forKey: .client)
        case .fetchHierarchy(let options):
            try c.encode("fetchHierarchy", forKey: .t); try c.encode(options, forKey: .options)
        case .fetchSnapshot(let nodeID, let scale):
            try c.encode("fetchSnapshot", forKey: .t); try c.encode(nodeID, forKey: .nodeID); try c.encode(scale, forKey: .scale)
        case .setAttribute(let nodeID, let keyPath, let value):
            try c.encode("setAttribute", forKey: .t)
            try c.encode(nodeID, forKey: .nodeID); try c.encode(keyPath, forKey: .keyPath); try c.encode(value, forKey: .value)
        case .highlight(let nodeID):
            try c.encode("highlight", forKey: .t); try c.encodeIfPresent(nodeID, forKey: .nodeID)
        case .ping:
            try c.encode("ping", forKey: .t)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .t) {
        case "handshake":      self = .handshake(try c.decode(ClientInfo.self, forKey: .client))
        case "fetchHierarchy": self = .fetchHierarchy(try c.decode(HierarchyOptions.self, forKey: .options))
        case "fetchSnapshot":  self = .fetchSnapshot(nodeID: try c.decode(String.self, forKey: .nodeID),
                                                     scale: try c.decode(Double.self, forKey: .scale))
        case "setAttribute":   self = .setAttribute(nodeID: try c.decode(String.self, forKey: .nodeID),
                                                    keyPath: try c.decode(String.self, forKey: .keyPath),
                                                    value: try c.decode(AttributeValue.self, forKey: .value))
        case "highlight":      self = .highlight(nodeID: try c.decodeIfPresent(String.self, forKey: .nodeID))
        case "ping":           self = .ping
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .t, in: c, debugDescription: "unknown ClientMessage \(other)")
        }
    }
}

extension ServerMessage: Codable {
    private enum CodingKeys: String, CodingKey {
        case t, info, snapshot, image, nodeID, keyPath, success, message, event, code
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .handshakeAck(let info):
            try c.encode("handshakeAck", forKey: .t); try c.encode(info, forKey: .info)
        case .hierarchy(let snap):
            try c.encode("hierarchy", forKey: .t); try c.encode(snap, forKey: .snapshot)
        case .snapshot(let image):
            try c.encode("snapshot", forKey: .t); try c.encode(image, forKey: .image)
        case .attributeResult(let nodeID, let keyPath, let success, let message):
            try c.encode("attributeResult", forKey: .t)
            try c.encode(nodeID, forKey: .nodeID); try c.encode(keyPath, forKey: .keyPath)
            try c.encode(success, forKey: .success); try c.encodeIfPresent(message, forKey: .message)
        case .event(let event):
            try c.encode("event", forKey: .t); try c.encode(event, forKey: .event)
        case .error(let code, let message):
            try c.encode("error", forKey: .t); try c.encode(code, forKey: .code); try c.encode(message, forKey: .message)
        case .pong:
            try c.encode("pong", forKey: .t)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .t) {
        case "handshakeAck": self = .handshakeAck(try c.decode(ServerInfo.self, forKey: .info))
        case "hierarchy":    self = .hierarchy(try c.decode(HierarchySnapshot.self, forKey: .snapshot))
        case "snapshot":     self = .snapshot(try c.decode(SnapshotImage.self, forKey: .image))
        case "attributeResult":
            self = .attributeResult(nodeID: try c.decode(String.self, forKey: .nodeID),
                                    keyPath: try c.decode(String.self, forKey: .keyPath),
                                    success: try c.decode(Bool.self, forKey: .success),
                                    message: try c.decodeIfPresent(String.self, forKey: .message))
        case "event":        self = .event(try c.decode(ServerEvent.self, forKey: .event))
        case "error":        self = .error(code: try c.decode(Int.self, forKey: .code),
                                           message: try c.decode(String.self, forKey: .message))
        case "pong":         self = .pong
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .t, in: c, debugDescription: "unknown ServerMessage \(other)")
        }
    }
}

extension ServerEvent: Codable {
    private enum CodingKeys: String, CodingKey { case t, reason, message }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .hierarchyChanged:
            try c.encode("hierarchyChanged", forKey: .t)
        case .willDisconnect(let reason):
            try c.encode("willDisconnect", forKey: .t); try c.encode(reason, forKey: .reason)
        case .log(let message):
            try c.encode("log", forKey: .t); try c.encode(message, forKey: .message)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .t) {
        case "hierarchyChanged": self = .hierarchyChanged
        case "willDisconnect":   self = .willDisconnect(reason: try c.decode(String.self, forKey: .reason))
        case "log":              self = .log(try c.decode(String.self, forKey: .message))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .t, in: c, debugDescription: "unknown ServerEvent \(other)")
        }
    }
}
