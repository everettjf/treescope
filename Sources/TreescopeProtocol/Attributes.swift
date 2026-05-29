import Foundation

/// A typed property value, rich enough for the inspector to render colors,
/// numbers, booleans, geometry and nested structures distinctly.
///
/// Encodes to a clean, discriminated JSON shape (`{"t": "...", "v": ...}`) that
/// the TypeScript viewer mirrors directly, instead of Swift's synthesized
/// `{"caseName": {"_0": ...}}` form.
public indirect enum AttributeValue: Hashable, Sendable {
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

extension AttributeValue: Codable {
    private enum CodingKeys: String, CodingKey { case t, v, w, h }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string(let s):      try c.encode("string", forKey: .t);    try c.encode(s, forKey: .v)
        case .number(let n):      try c.encode("number", forKey: .t);    try c.encode(n, forKey: .v)
        case .integer(let i):     try c.encode("integer", forKey: .t);   try c.encode(i, forKey: .v)
        case .bool(let b):        try c.encode("bool", forKey: .t);      try c.encode(b, forKey: .v)
        case .enumeration(let e): try c.encode("enum", forKey: .t);      try c.encode(e, forKey: .v)
        case .color(let col):     try c.encode("color", forKey: .t);     try c.encode(col, forKey: .v)
        case .point(let p):       try c.encode("point", forKey: .t);     try c.encode(p, forKey: .v)
        case .size(let s):        try c.encode("size", forKey: .t);      try c.encode(s, forKey: .v)
        case .rect(let r):        try c.encode("rect", forKey: .t);      try c.encode(r, forKey: .v)
        case .insets(let i):      try c.encode("insets", forKey: .t);    try c.encode(i, forKey: .v)
        case .reference(let r):   try c.encode("reference", forKey: .t); try c.encode(r, forKey: .v)
        case .null:               try c.encode("null", forKey: .t)
        case .image(let w, let h):
            try c.encode("image", forKey: .t); try c.encode(w, forKey: .w); try c.encode(h, forKey: .h)
        case .nested(let a):      try c.encode("nested", forKey: .t);    try c.encode(a, forKey: .v)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let t = try c.decode(String.self, forKey: .t)
        switch t {
        case "string":    self = .string(try c.decode(String.self, forKey: .v))
        case "number":    self = .number(try c.decode(Double.self, forKey: .v))
        case "integer":   self = .integer(try c.decode(Int.self, forKey: .v))
        case "bool":      self = .bool(try c.decode(Bool.self, forKey: .v))
        case "enum":      self = .enumeration(try c.decode(String.self, forKey: .v))
        case "color":     self = .color(try c.decode(RGBAColor.self, forKey: .v))
        case "point":     self = .point(try c.decode(Point.self, forKey: .v))
        case "size":      self = .size(try c.decode(Size.self, forKey: .v))
        case "rect":      self = .rect(try c.decode(Rect.self, forKey: .v))
        case "insets":    self = .insets(try c.decode(EdgeInsets.self, forKey: .v))
        case "reference": self = .reference(try c.decode(String.self, forKey: .v))
        case "null":      self = .null
        case "image":     self = .image(width: try c.decode(Int.self, forKey: .w),
                                        height: try c.decode(Int.self, forKey: .h))
        case "nested":    self = .nested(try c.decode([Attribute].self, forKey: .v))
        default:
            throw DecodingError.dataCorruptedError(forKey: .t, in: c,
                debugDescription: "unknown AttributeValue type \(t)")
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
