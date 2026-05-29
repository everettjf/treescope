import Foundation

/// Which rendering framework a node originated from.
public enum ViewKind: String, Codable, Hashable, Sendable {
    case window
    case uiView          // UIKit UIView
    case uiViewController
    case caLayer         // CALayer (UIKit/AppKit backing layer)
    case nsView          // AppKit NSView
    case nsViewController
    case nsWindow
    case swiftUI         // a reflected SwiftUI view value
    case hostingView     // a UIHostingView / NSHostingView bridging SwiftUI<->platform
    case other

    public var isSwiftUI: Bool { self == .swiftUI }
    public var isPlatformView: Bool {
        switch self {
        case .uiView, .nsView, .caLayer, .window, .nsWindow, .hostingView: return true
        default: return false
        }
    }
}

/// Flags describing notable traits of a node, used for filtering/badging.
public struct ViewFlags: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let hidden          = ViewFlags(rawValue: 1 << 0)
    public static let clipsToBounds   = ViewFlags(rawValue: 1 << 1)
    public static let userInteraction = ViewFlags(rawValue: 1 << 2)
    public static let systemView      = ViewFlags(rawValue: 1 << 3) // Apple-internal
    public static let hostsSwiftUI    = ViewFlags(rawValue: 1 << 4)
    public static let hasSnapshot     = ViewFlags(rawValue: 1 << 5)
    public static let zeroSize        = ViewFlags(rawValue: 1 << 6)
    public static let offscreen       = ViewFlags(rawValue: 1 << 7)
}

/// One node in the captured hierarchy tree.
public struct ViewNode: Codable, Hashable, Identifiable, Sendable {
    /// Stable identity for the lifetime of a snapshot.
    public var id: String
    public var kind: ViewKind
    /// Full type name, e.g. "UILabel" or "ModifiedContent<Text, _PaddingLayout>".
    public var className: String
    /// Friendly short name shown in the tree, e.g. "Text" or "VStack".
    public var displayName: String
    /// Optional accessibility identifier / label to aid recognition.
    public var label: String?

    /// Frame in the coordinate space of the root window (absolute), in points.
    public var frame: Rect
    /// Local bounds.
    public var bounds: Rect
    public var opacity: Double
    public var flags: ViewFlags
    /// Depth ordering hint within the parent (z position).
    public var zIndex: Double
    public var transform: Transform3D?

    /// Grouped, inspectable properties.
    public var sections: [AttributeSection]
    /// Identifier used to lazily fetch a rendered snapshot image for this node.
    public var snapshotID: String?

    public var children: [ViewNode]

    public init(id: String,
                kind: ViewKind,
                className: String,
                displayName: String,
                label: String? = nil,
                frame: Rect,
                bounds: Rect,
                opacity: Double = 1,
                flags: ViewFlags = [],
                zIndex: Double = 0,
                transform: Transform3D? = nil,
                sections: [AttributeSection] = [],
                snapshotID: String? = nil,
                children: [ViewNode] = []) {
        self.id = id
        self.kind = kind
        self.className = className
        self.displayName = displayName
        self.label = label
        self.frame = frame
        self.bounds = bounds
        self.opacity = opacity
        self.flags = flags
        self.zIndex = zIndex
        self.transform = transform
        self.sections = sections
        self.snapshotID = snapshotID
        self.children = children
    }

    // MARK: Tree helpers

    /// Total node count including self.
    public var subtreeCount: Int {
        1 + children.reduce(0) { $0 + $1.subtreeCount }
    }

    /// Depth-first pre-order traversal.
    public func forEachDepthFirst(_ body: (ViewNode) -> Void) {
        body(self)
        for child in children { child.forEachDepthFirst(body) }
    }

    /// Finds a node by id anywhere in the subtree.
    public func node(withID id: String) -> ViewNode? {
        if self.id == id { return self }
        for child in children {
            if let found = child.node(withID: id) { return found }
        }
        return nil
    }

    /// Path of ids from this node down to the node with the given id, inclusive.
    public func path(toID target: String) -> [String]? {
        if id == target { return [id] }
        for child in children {
            if let sub = child.path(toID: target) { return [id] + sub }
        }
        return nil
    }
}
