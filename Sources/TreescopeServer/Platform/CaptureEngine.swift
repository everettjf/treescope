import Foundation
import TreescopeProtocol
#if canImport(QuartzCore)
import QuartzCore
#endif

/// Weak holder so the snapshot registry never extends a view's lifetime.
final class WeakObject {
    weak var value: AnyObject?
    init(_ value: AnyObject) { self.value = value }
}

/// Builds a `HierarchySnapshot` from the live UIKit/AppKit/SwiftUI scene and
/// renders per-node snapshot images on demand.
///
/// Must be driven on the main thread (it touches UIKit/AppKit). The transport
/// layer hops to main before calling these methods.
public final class CaptureEngine {

    let ids = NodeIDFactory()
    /// Maps node id -> live object, refreshed on each capture, used for lazy
    /// snapshot rendering and live attribute edits.
    private(set) var registry: [String: WeakObject] = [:]
    /// The current on-device highlight overlay, if any.
    var highlightRef: WeakObject?

    /// Looks up the live object backing a node id.
    func object(for nodeID: String) -> AnyObject? { registry[nodeID]?.value }

    public init() {}

    public var capabilities: ServerInfo.Capabilities {
        var caps: ServerInfo.Capabilities = [.snapshots, .swiftUI, .highlighting, .pushUpdates]
        #if canImport(UIKit) || canImport(AppKit)
        caps.insert(.liveEditing)
        #endif
        return caps
    }

    /// Captures the full hierarchy. Platform extensions provide `captureRoots`.
    public func captureHierarchy(options: HierarchyOptions = .default) -> HierarchySnapshot {
        registry.removeAll(keepingCapacity: true)
        let roots = captureRoots(options: options)
        return HierarchySnapshot(device: makeDeviceInfo(), roots: roots)
    }

    /// Renders a snapshot image for a node, if its object is still alive.
    public func snapshotImage(nodeID: String, scale: Double) -> SnapshotImage? {
        guard let object = registry[nodeID]?.value else { return nil }
        #if canImport(QuartzCore)
        if let layer = object as? CALayer { return renderLayerSnapshot(layer, nodeID: nodeID, scale: scale) }
        #endif
        return renderSnapshot(object: object, nodeID: nodeID, scale: scale)
    }

    /// Attempts a live attribute edit. Returns (success, message).
    public func applyAttribute(nodeID: String, keyPath: String, value: AttributeValue) -> (Bool, String?) {
        guard let object = registry[nodeID]?.value else {
            return (false, "node no longer exists")
        }
        #if canImport(QuartzCore)
        if let layer = object as? CALayer { return setLayerAttribute(on: layer, keyPath: keyPath, value: value) }
        #endif
        return setAttribute(on: object, keyPath: keyPath, value: value)
    }

    // MARK: Registry helpers used by platform walkers

    func register(_ object: AnyObject) -> String {
        let id = ids.id(for: object)
        registry[id] = WeakObject(object)
        return id
    }

    func registerValueNode(path: String) -> String {
        ids.id(path: path)
    }
}
