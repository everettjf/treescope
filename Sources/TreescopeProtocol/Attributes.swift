import Foundation

/// A typed property value, rich enough for the inspector to render colors,
/// numbers, booleans, geometry and nested structures distinctly.
public indirect enum AttributeValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case integer(Int)
    case bool(Bool)
    case color(RGBAColor)
    case point(Point)
    case size(Size)
    case rect(Rect)
    case insets(EdgeInsets)
    case enumeration(String)            // e.g. ".center", "fill"
    case image(width: Int, height: Int) // an image-valued property (e.g. UIImage)
    case reference(String)              // a class/identity reference rendered as text
    case null
    case nested([Attribute])            // grouped / composite value

    /// A flat, human-readable rendering used in compact contexts.
    public var displayString: String {
        switch self {
        case .string(let s): return s
        case .number(let d):
            if d == d.rounded() && abs(d) < 1e15 { return String(format: "%.1f", d) }
            return String(format: "%g", d)
        case .integer(let i): return String(i)
        case .bool(let b): return b ? "true" : "false"
        case .color(let c): return c.hexString
        case .point(let p): return String(format: "(%.1f, %.1f)", p.x, p.y)
        case .size(let s): return String(format: "%.1f × %.1f", s.width, s.height)
        case .rect(let r): return String(format: "{%.1f, %.1f, %.1f, %.1f}", r.x, r.y, r.width, r.height)
        case .insets(let i): return String(format: "(%.0f, %.0f, %.0f, %.0f)", i.top, i.left, i.bottom, i.right)
        case .enumeration(let e): return e
        case .image(let w, let h): return "Image \(w)×\(h)"
        case .reference(let r): return r
        case .null: return "nil"
        case .nested(let attrs): return "{ \(attrs.count) }"
        }
    }
}

/// A single inspectable property.
public struct Attribute: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var value: AttributeValue
    /// Whether the viewer may attempt a live edit (best-effort, server decides).
    public var editable: Bool
    /// Key path the server understands for live editing, when editable.
    public var keyPath: String?

    public init(id: String? = nil,
                title: String,
                value: AttributeValue,
                editable: Bool = false,
                keyPath: String? = nil) {
        self.id = id ?? title
        self.title = title
        self.value = value
        self.editable = editable
        self.keyPath = keyPath
    }
}

/// A named group of attributes, e.g. "Layout", "Appearance", "SwiftUI".
public struct AttributeSection: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var attributes: [Attribute]

    public init(id: String? = nil, title: String, attributes: [Attribute]) {
        self.id = id ?? title
        self.title = title
        self.attributes = attributes
    }
}

public extension Array where Element == AttributeSection {
    /// Convenience for building sections, dropping empty ones.
    static func build(_ sections: [(String, [Attribute])]) -> [AttributeSection] {
        sections.compactMap { title, attrs in
            attrs.isEmpty ? nil : AttributeSection(title: title, attributes: attrs)
        }
    }
}
