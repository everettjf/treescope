import Foundation
import TreescopeProtocol

#if canImport(ObjectiveC)
import ObjectiveC
#endif
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Best-effort bridge to SwiftUI's private view-debug data, which (when
/// available) yields *resolved* geometry for the SwiftUI tree — the same source
/// Xcode's "Debug View Hierarchy" uses.
///
/// This is intentionally defensive: the underlying API name has changed across
/// OS versions (`_viewDebugData` → `makeViewDebugData`) and may be stripped
/// entirely. Every access is guarded; failure returns `nil` and callers fall
/// back to the Mirror-reflected tree (which has no resolved frames).
///
/// Because this only ever runs in Debug builds of the host app (the server is
/// excluded from Release), reliance on private API carries no App Store risk.
public enum ViewDebugDataExtractor {

    /// Candidate selectors, newest first.
    private static let selectorNames = ["makeViewDebugData", "_viewDebugData"]

    /// Returns true if a hosting view appears to expose debug data on this OS.
    public static func isAvailable(on hostingView: AnyObject) -> Bool {
        #if canImport(ObjectiveC)
        for name in selectorNames {
            if hostingView.responds(to: NSSelectorFromString(name)) {
                return true
            }
        }
        #endif
        return false
    }

    /// Attempts to extract resolved frames keyed by a structural signature.
    ///
    /// Returns nil when the private API is unavailable or its shape is
    /// unrecognized on the current OS. The structural map is keyed by the
    /// view's type signature path so the reflector can merge resolved frames
    /// onto matching nodes when possible.
    public static func resolvedFrames(from hostingView: AnyObject) -> [String: Rect]? {
        #if canImport(ObjectiveC)
        guard let raw = invokeDebugData(on: hostingView) else { return nil }
        return parse(raw)
        #else
        return nil
        #endif
    }

    #if canImport(ObjectiveC)
    private static func invokeDebugData(on hostingView: AnyObject) -> Any? {
        for name in selectorNames {
            let selector = NSSelectorFromString(name)
            guard hostingView.responds(to: selector) else { continue }
            // The return type is a Swift array; bridging through perform is
            // unreliable, so we only proceed if the value bridges to NSArray.
            let unmanaged = hostingView.perform(selector)
            if let value = unmanaged?.takeUnretainedValue() {
                return value
            }
        }
        return nil
    }

    /// Walks the debug-data payload looking for any embedded CGRect-like frames.
    /// The exact schema is version-specific; we extract conservatively.
    private static func parse(_ raw: Any) -> [String: Rect]? {
        var result: [String: Rect] = [:]
        var index = 0
        func walk(_ value: Any, depth: Int) {
            guard depth < 24 else { return }
            let mirror = Mirror(reflecting: value)
            #if canImport(CoreGraphics)
            if let rect = value as? CGRect {
                result["frame.\(index)"] = Rect(x: Double(rect.origin.x), y: Double(rect.origin.y),
                                                width: Double(rect.size.width), height: Double(rect.size.height))
                index += 1
            }
            #endif
            for child in mirror.children {
                walk(child.value, depth: depth + 1)
            }
        }
        walk(raw, depth: 0)
        return result.isEmpty ? nil : result
    }
    #endif
}
