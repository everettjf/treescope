import Foundation

/// Produces stable-within-a-snapshot identifiers for captured nodes.
///
/// Reference types (UIView/NSView/CALayer) key off their object identity so the
/// same view keeps its id across captures. Value-type SwiftUI nodes have no
/// identity, so they key off their structural path within the tree.
public struct NodeIDFactory {
    public init() {}

    public func id(for object: AnyObject) -> String {
        let bits = UInt(bitPattern: ObjectIdentifier(object).hashValue)
        return "obj:" + String(bits, radix: 16)
    }

    public func id(path: String) -> String {
        "sui:" + path
    }
}
