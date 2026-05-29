import SwiftUI
import TreescopeProtocol

#if canImport(AppKit)
import AppKit
#endif

extension RGBAColor {
    var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

extension Rect {
    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

enum ColorBridge {
    static func rgba(from color: Color) -> RGBAColor {
        #if canImport(AppKit)
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        return RGBAColor(red: Double(ns.redComponent), green: Double(ns.greenComponent),
                         blue: Double(ns.blueComponent), alpha: Double(ns.alphaComponent))
        #else
        return RGBAColor(red: 0, green: 0, blue: 0, alpha: 1)
        #endif
    }
}

enum ImageDecoder {
    #if canImport(AppKit)
    static func image(from snapshot: SnapshotImage) -> Image? {
        guard let nsImage = NSImage(data: snapshot.data) else { return nil }
        return Image(nsImage: nsImage)
    }
    #else
    static func image(from snapshot: SnapshotImage) -> Image? { nil }
    #endif
}

extension ViewKind {
    var symbolName: String {
        switch self {
        case .window, .nsWindow: return "macwindow"
        case .uiView, .nsView: return "rectangle.dashed"
        case .uiViewController, .nsViewController: return "rectangle.stack"
        case .caLayer: return "square.stack.3d.up"
        case .swiftUI: return "swift"
        case .hostingView: return "square.on.square.dashed"
        case .other: return "questionmark.square.dashed"
        }
    }

    var tintColor: Color {
        switch self {
        case .swiftUI, .hostingView: return .orange
        case .window, .nsWindow: return .purple
        case .uiViewController, .nsViewController: return .pink
        case .caLayer: return .teal
        default: return .blue
        }
    }
}

extension ViewNode {
    /// A short subtitle for tree rows.
    var subtitle: String? {
        if let label, !label.isEmpty { return label }
        if frame.size.area == 0 { return "0 × 0" }
        return String(format: "%.0f × %.0f", frame.width, frame.height)
    }
}
