import Foundation

// Plain, Codable geometry primitives so the protocol stays free of any
// CoreGraphics / UIKit dependency and remains portable (incl. Linux tooling).

public struct Point: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
    public static let zero = Point(x: 0, y: 0)
}

public struct Size: Codable, Hashable, Sendable {
    public var width: Double
    public var height: Double
    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
    public static let zero = Size(width: 0, height: 0)
    public var area: Double { max(0, width) * max(0, height) }
}

public struct Rect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let zero = Rect(x: 0, y: 0, width: 0, height: 0)

    public var origin: Point { Point(x: x, y: y) }
    public var size: Size { Size(width: width, height: height) }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var center: Point { Point(x: midX, y: midY) }

    public func contains(_ p: Point) -> Bool {
        p.x >= x && p.x <= maxX && p.y >= y && p.y <= maxY
    }

    /// Offsets this rect from a parent's coordinate space into the parent's parent.
    public func offset(by p: Point) -> Rect {
        Rect(x: x + p.x, y: y + p.y, width: width, height: height)
    }
}

public struct EdgeInsets: Codable, Hashable, Sendable {
    public var top: Double
    public var left: Double
    public var bottom: Double
    public var right: Double
    public init(top: Double, left: Double, bottom: Double, right: Double) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }
    public static let zero = EdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
}

/// sRGB color with straight alpha, components in 0...1.
public struct RGBAColor: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double
    public init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public var hexString: String {
        func c(_ v: Double) -> Int { Int((max(0, min(1, v)) * 255).rounded()) }
        if alpha >= 1.0 {
            return String(format: "#%02X%02X%02X", c(red), c(green), c(blue))
        }
        return String(format: "#%02X%02X%02X%02X", c(red), c(green), c(blue), c(alpha))
    }
}

/// A 4x4 transform matrix stored row-major. Identity when nil-equivalent.
public struct Transform3D: Codable, Hashable, Sendable {
    public var m: [Double] // 16 values, row-major
    public init(m: [Double]) {
        precondition(m.count == 16, "Transform3D requires 16 values")
        self.m = m
    }
    public static let identity = Transform3D(m: [
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    ])
    public var isIdentity: Bool { self == .identity }
}
