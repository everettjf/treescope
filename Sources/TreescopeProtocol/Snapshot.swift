import Foundation

/// Metadata about the host device/app, captured alongside a hierarchy.
public struct DeviceInfo: Codable, Hashable, Sendable {
    public var appName: String
    public var bundleID: String
    public var processName: String
    public var osName: String        // "iOS", "macOS", "tvOS"
    public var osVersion: String
    public var deviceModel: String
    public var deviceName: String
    public var screenSize: Size
    public var screenScale: Double
    public var isSimulator: Bool

    public init(appName: String,
                bundleID: String,
                processName: String,
                osName: String,
                osVersion: String,
                deviceModel: String,
                deviceName: String,
                screenSize: Size,
                screenScale: Double,
                isSimulator: Bool) {
        self.appName = appName
        self.bundleID = bundleID
        self.processName = processName
        self.osName = osName
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.deviceName = deviceName
        self.screenSize = screenSize
        self.screenScale = screenScale
        self.isSimulator = isSimulator
    }
}

/// A complete captured view hierarchy plus device context.
public struct HierarchySnapshot: Codable, Hashable, Sendable {
    public var device: DeviceInfo
    public var roots: [ViewNode]
    /// Seconds since 1970 when captured.
    public var timestamp: Double
    public var serverVersion: String

    public init(device: DeviceInfo,
                roots: [ViewNode],
                timestamp: Double = Date().timeIntervalSince1970,
                serverVersion: String = ProtocolConstants.version) {
        self.device = device
        self.roots = roots
        self.timestamp = timestamp
        self.serverVersion = serverVersion
    }

    public var totalNodeCount: Int { roots.reduce(0) { $0 + $1.subtreeCount } }

    public func node(withID id: String) -> ViewNode? {
        for root in roots {
            if let n = root.node(withID: id) { return n }
        }
        return nil
    }
}

/// Identifies the connecting viewer to the server.
public struct ClientInfo: Codable, Hashable, Sendable {
    public var name: String
    public var version: String
    public var protocolVersion: Int
    public init(name: String, version: String, protocolVersion: Int = ProtocolConstants.protocolVersion) {
        self.name = name
        self.version = version
        self.protocolVersion = protocolVersion
    }
}

/// Server's response to a handshake.
public struct ServerInfo: Codable, Hashable, Sendable {
    public var device: DeviceInfo
    public var serverVersion: String
    public var protocolVersion: Int
    public var capabilities: Capabilities

    public struct Capabilities: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let snapshots     = Capabilities(rawValue: 1 << 0)
        public static let liveEditing   = Capabilities(rawValue: 1 << 1)
        public static let swiftUI       = Capabilities(rawValue: 1 << 2)
        public static let highlighting  = Capabilities(rawValue: 1 << 3)
        public static let pushUpdates   = Capabilities(rawValue: 1 << 4)
    }

    public init(device: DeviceInfo,
                serverVersion: String = ProtocolConstants.version,
                protocolVersion: Int = ProtocolConstants.protocolVersion,
                capabilities: Capabilities) {
        self.device = device
        self.serverVersion = serverVersion
        self.protocolVersion = protocolVersion
        self.capabilities = capabilities
    }
}

/// Encoded image payload for a node snapshot.
public struct SnapshotImage: Codable, Hashable, Sendable {
    public var nodeID: String
    public var format: ImageFormat
    public var scale: Double
    public var pixelSize: Size
    public var data: Data

    public enum ImageFormat: String, Codable, Sendable {
        case png
        case jpeg
    }

    public init(nodeID: String, format: ImageFormat, scale: Double, pixelSize: Size, data: Data) {
        self.nodeID = nodeID
        self.format = format
        self.scale = scale
        self.pixelSize = pixelSize
        self.data = data
    }
}
