import Foundation
import TreescopeProtocol

#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif

/// Converts arbitrary runtime values into the protocol's typed `AttributeValue`,
/// so the inspector can render colors, geometry, numbers and enums distinctly.
public enum ValueDescriber {

    /// Maximum recursion depth when unwrapping optionals / nested mirrors.
    private static let maxDepth = 6
    private static let maxStringLength = 240

    public static func describe(_ value: Any, depth: Int = 0) -> AttributeValue {
        if depth > maxDepth { return .string(truncate(String(describing: value))) }

        // Unwrap optionals first so `.none` becomes a clean nil.
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            if let child = mirror.children.first {
                return describe(child.value, depth: depth + 1)
            }
            return .null
        }

        // Scalars.
        switch value {
        case let v as String:  return .string(truncate(v))
        case let v as Bool:    return .bool(v)
        case let v as Int:     return .integer(v)
        case let v as Int8:    return .integer(Int(v))
        case let v as Int16:   return .integer(Int(v))
        case let v as Int32:   return .integer(Int(v))
        case let v as Int64:   return .integer(Int(v))
        case let v as UInt:    return .integer(Int(truncatingIfNeeded: v))
        case let v as UInt32:  return .integer(Int(v))
        case let v as UInt64:  return .integer(Int(truncatingIfNeeded: v))
        case let v as Double:  return .number(v)
        case let v as Float:   return .number(Double(v))
        default: break
        }

        #if canImport(CoreGraphics)
        switch value {
        case let v as CGFloat: return .number(Double(v))
        case let v as CGPoint: return .point(Point(x: Double(v.x), y: Double(v.y)))
        case let v as CGSize:  return .size(Size(width: Double(v.width), height: Double(v.height)))
        case let v as CGRect:
            return .rect(Rect(x: Double(v.origin.x), y: Double(v.origin.y),
                              width: Double(v.size.width), height: Double(v.size.height)))
        default: break
        }
        #endif

        if let color = colorValue(value) {
            return .color(color)
        }

        #if canImport(UIKit)
        if let insets = value as? UIEdgeInsets {
            return .insets(EdgeInsets(top: Double(insets.top), left: Double(insets.left),
                                      bottom: Double(insets.bottom), right: Double(insets.right)))
        }
        if value is UIImage {
            let img = value as! UIImage
            return .image(width: Int(img.size.width), height: Int(img.size.height))
        }
        #endif
        #if canImport(AppKit)
        if let insets = value as? NSEdgeInsets {
            return .insets(EdgeInsets(top: Double(insets.top), left: Double(insets.left),
                                      bottom: Double(insets.bottom), right: Double(insets.right)))
        }
        if let img = value as? NSImage {
            return .image(width: Int(img.size.width), height: Int(img.size.height))
        }
        #endif

        // Enums without payload render as their case name.
        if mirror.displayStyle == .enum {
            if mirror.children.isEmpty {
                return .enumeration(String(describing: value))
            }
            // Enum with an associated value: show "case(payload)".
            return .enumeration(truncate(String(describing: value)))
        }

        // Class instances: show a compact type reference.
        if mirror.displayStyle == .class {
            return .reference(typeName(of: value))
        }

        return .string(truncate(String(describing: value)))
    }

    /// Extracts color components from UIColor / NSColor / CGColor / SwiftUI.Color.
    public static func colorValue(_ value: Any) -> RGBAColor? {
        #if canImport(UIKit)
        if let c = value as? UIColor {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            if c.getRed(&r, green: &g, blue: &b, alpha: &a) {
                return RGBAColor(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
            }
        }
        #endif
        #if canImport(AppKit)
        if let c = value as? NSColor {
            if let rgb = c.usingColorSpace(.sRGB) {
                return RGBAColor(red: Double(rgb.redComponent), green: Double(rgb.greenComponent),
                                 blue: Double(rgb.blueComponent), alpha: Double(rgb.alphaComponent))
            }
        }
        #endif
        #if canImport(CoreGraphics)
        if CFGetTypeID(value as CFTypeRef) == CGColor.typeID {
            let c = value as! CGColor
            if let comps = c.components, comps.count >= 3 {
                let a = comps.count >= 4 ? comps[3] : 1
                return RGBAColor(red: Double(comps[0]), green: Double(comps[1]),
                                 blue: Double(comps[2]), alpha: Double(a))
            }
        }
        #endif
        return nil
    }

    /// Finds the first `String` value reachable from a value's mirror tree.
    /// Used to recover e.g. the content of a SwiftUI `Text`.
    public static func firstString(in value: Any, depth: Int = 0) -> String? {
        if let s = value as? String { return s }
        if depth > maxDepth { return nil }
        let mirror = Mirror(reflecting: value)
        for child in mirror.children {
            if let s = firstString(in: child.value, depth: depth + 1) {
                return s
            }
        }
        return nil
    }

    // MARK: - Type names

    /// Short, human-friendly type name, e.g. "Text" or "MyButton".
    public static func shortTypeName(of value: Any) -> String {
        baseName(typeName(of: value))
    }

    public static func typeName(of value: Any) -> String {
        String(reflecting: type(of: value))
    }

    /// Strips module qualifiers and generic parameters: "SwiftUI.Text<...>" -> "Text".
    public static func baseName(_ fullName: String) -> String {
        // Drop generic arguments.
        var name = fullName
        if let angle = name.firstIndex(of: "<") {
            name = String(name[..<angle])
        }
        // Drop module / namespace prefixes.
        if let dot = name.lastIndex(of: ".") {
            name = String(name[name.index(after: dot)...])
        }
        return name
    }

    private static func truncate(_ s: String) -> String {
        if s.count <= maxStringLength { return s }
        return String(s.prefix(maxStringLength)) + "…"
    }
}
