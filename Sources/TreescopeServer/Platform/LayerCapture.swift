#if canImport(QuartzCore)
import QuartzCore
import TreescopeProtocol

#if canImport(UIKit)
import UIKit
private typealias PlatformView = UIView
#elseif canImport(AppKit)
import AppKit
private typealias PlatformView = NSView
#endif

/// CALayer traversal + inspection. Walking a view's standalone sublayers (those
/// not owned by a subview) gives `.caLayer` nodes with *resolved* geometry —
/// which is also what gives a SwiftUI hosting view real rendered rectangles on
/// the canvas, since modern SwiftUI renders into a display-list layer tree.
extension CaptureEngine {

    /// Captures the standalone sublayers of `layer` (skipping subview-backing
    /// layers, which are already represented by their view nodes).
    func captureLayerChildren(of layer: CALayer, absoluteOrigin: Point, options: HierarchyOptions,
                              path: String, depth: Int) -> [ViewNode] {
        guard let sublayers = layer.sublayers, depth < 80 else { return [] }
        var out: [ViewNode] = []
        for (i, sub) in sublayers.enumerated() where !isViewBacked(sub) {
            out.append(captureLayer(sub, absoluteOrigin: absoluteOrigin, options: options,
                                    path: "\(path)/L\(i)", depth: depth + 1))
        }
        return out
    }

    private func captureLayer(_ layer: CALayer, absoluteOrigin: Point, options: HierarchyOptions,
                              path: String, depth: Int) -> ViewNode {
        let id = register(layer)
        let f = layer.frame
        let absolute = Rect(x: absoluteOrigin.x + Double(f.origin.x),
                            y: absoluteOrigin.y + Double(f.origin.y),
                            width: Double(f.size.width), height: Double(f.size.height))

        var flags: ViewFlags = []
        if layer.isHidden { flags.insert(.hidden) }
        if layer.bounds.isEmpty { flags.insert(.zeroSize) }

        let children = captureLayerChildren(of: layer,
                                            absoluteOrigin: Point(x: absolute.x, y: absolute.y),
                                            options: options, path: path, depth: depth)

        let className = NSStringFromClass(type(of: layer))
        return ViewNode(
            id: id,
            kind: .caLayer,
            className: className,
            displayName: ValueDescriber.baseName(className),
            label: layer.name,
            frame: absolute,
            bounds: rect(layer.bounds),
            opacity: Double(layer.opacity),
            flags: flags,
            zIndex: Double(layer.zPosition),
            transform: transform(layer),
            sections: layerSections(layer),
            snapshotID: options.requestSnapshots && !layer.bounds.isEmpty ? id : nil,
            children: children)
    }

    private func isViewBacked(_ layer: CALayer) -> Bool {
        #if canImport(UIKit) || canImport(AppKit)
        return layer.delegate is PlatformView
        #else
        return false
        #endif
    }

    func layerSections(_ layer: CALayer) -> [AttributeSection] {
        let geometry: [Attribute] = [
            Attribute(title: "frame", value: .rect(rect(layer.frame))),
            Attribute(title: "bounds", value: .rect(rect(layer.bounds))),
            Attribute(title: "position", value: .point(Point(x: Double(layer.position.x), y: Double(layer.position.y)))),
            Attribute(title: "zPosition", value: .number(Double(layer.zPosition))),
        ]
        var appearance: [Attribute] = [
            Attribute(title: "opacity", value: .number(Double(layer.opacity)), editable: true, keyPath: "opacity"),
            Attribute(title: "hidden", value: .bool(layer.isHidden), editable: true, keyPath: "hidden"),
            Attribute(title: "cornerRadius", value: .number(Double(layer.cornerRadius)), editable: true, keyPath: "cornerRadius"),
            Attribute(title: "borderWidth", value: .number(Double(layer.borderWidth)), editable: true, keyPath: "borderWidth"),
            Attribute(title: "masksToBounds", value: .bool(layer.masksToBounds)),
        ]
        if let bg = layer.backgroundColor, let c = ValueDescriber.colorValue(bg) {
            appearance.append(Attribute(title: "backgroundColor", value: .color(c), editable: true, keyPath: "backgroundColor"))
        }
        if let bc = layer.borderColor, let c = ValueDescriber.colorValue(bc) {
            appearance.append(Attribute(title: "borderColor", value: .color(c)))
        }
        if layer.shadowOpacity > 0 {
            appearance.append(Attribute(title: "shadowOpacity", value: .number(Double(layer.shadowOpacity))))
            appearance.append(Attribute(title: "shadowRadius", value: .number(Double(layer.shadowRadius))))
        }
        var content: [Attribute] = []
        if layer.contents != nil {
            content.append(Attribute(title: "contents", value: .reference("<image>")))
            content.append(Attribute(title: "contentsScale", value: .number(Double(layer.contentsScale))))
        }
        return [AttributeSection].build([
            ("Geometry", geometry),
            ("Appearance", appearance),
            ("Content", content),
        ])
    }

    // MARK: Live edit / snapshot / highlight on layers

    func setLayerAttribute(on layer: CALayer, keyPath: String, value: AttributeValue) -> (Bool, String?) {
        let value = value.coercingIntegerToNumber
        switch (keyPath, value) {
        case ("opacity", .number(let n)): layer.opacity = Float(n); return (true, nil)
        case ("hidden", .bool(let b)): layer.isHidden = b; return (true, nil)
        case ("cornerRadius", .number(let n)): layer.cornerRadius = CGFloat(n); return (true, nil)
        case ("borderWidth", .number(let n)): layer.borderWidth = CGFloat(n); return (true, nil)
        case ("backgroundColor", .color(let c)):
            layer.backgroundColor = CGColor(red: CGFloat(c.red), green: CGFloat(c.green),
                                            blue: CGFloat(c.blue), alpha: CGFloat(c.alpha))
            return (true, nil)
        default:
            return (false, "cannot set layer '\(keyPath)' (unsupported key path or value type \(value.displayString))")
        }
    }

    func renderLayerSnapshot(_ layer: CALayer, nodeID: String, scale: Double) -> SnapshotImage? {
        let bounds = layer.bounds
        guard !bounds.isEmpty else { return nil }
        let renderScale = max(1.0, min(scale, 3.0))
        let width = Int(bounds.width * CGFloat(renderScale))
        let height = Int(bounds.height * CGFloat(renderScale))
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: CGFloat(renderScale), y: CGFloat(renderScale))
        layer.render(in: ctx)
        guard let cg = ctx.makeImage(), let data = pngData(from: cg) else { return nil }
        return SnapshotImage(nodeID: nodeID, format: .png, scale: renderScale,
                             pixelSize: Size(width: Double(width), height: Double(height)), data: data)
    }

    private func pngData(from cgImage: CGImage) -> Data? {
        #if canImport(UIKit)
        return UIImage(cgImage: cgImage).pngData()
        #elseif canImport(AppKit)
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
        #else
        return nil
        #endif
    }

    func highlightLayer(_ layer: CALayer) -> Bool {
        clearHighlightOverlay()
        let overlay = CALayer()
        overlay.frame = layer.bounds
        overlay.backgroundColor = CGColor(red: 0.2, green: 0.5, blue: 1, alpha: 0.18)
        overlay.borderColor = CGColor(red: 0.2, green: 0.5, blue: 1, alpha: 1)
        overlay.borderWidth = 1
        overlay.name = "treescope.highlight"
        layer.addSublayer(overlay)
        highlightRef = WeakObject(overlay)
        return true
    }

    /// Removes a previous highlight overlay, whether it was a view or a layer.
    func clearHighlightOverlay() {
        guard let prev = highlightRef?.value else { return }
        if let l = prev as? CALayer {
            l.removeFromSuperlayer()
        } else {
            #if canImport(UIKit)
            (prev as? UIView)?.removeFromSuperview()
            #elseif canImport(AppKit)
            (prev as? NSView)?.removeFromSuperview()
            #endif
        }
        highlightRef = nil
    }
}
#endif
