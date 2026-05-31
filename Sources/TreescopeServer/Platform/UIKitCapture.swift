#if canImport(UIKit)
import UIKit
import TreescopeProtocol

extension CaptureEngine {

    func makeDeviceInfo() -> DeviceInfo {
        let screen = UIScreen.main
        let device = UIDevice.current
        #if targetEnvironment(simulator)
        let isSim = true
        #else
        let isSim = false
        #endif
        let info = ProcessInfo.processInfo
        return DeviceInfo(
            appName: (Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String)
                ?? (Bundle.main.infoDictionary?["CFBundleName"] as? String)
                ?? info.processName,
            bundleID: Bundle.main.bundleIdentifier ?? "unknown",
            processName: info.processName,
            osName: device.systemName,
            osVersion: device.systemVersion,
            deviceModel: modelIdentifier(),
            deviceName: device.name,
            screenSize: Size(width: Double(screen.bounds.width), height: Double(screen.bounds.height)),
            screenScale: Double(screen.scale),
            isSimulator: isSim)
    }

    private func modelIdentifier() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafeBytes(of: &sysinfo.machine) { raw -> String in
            let data = Data(raw.prefix(while: { $0 != 0 }))
            return String(data: data, encoding: .utf8) ?? "Unknown"
        }
        return machine
    }

    func captureRoots(options: HierarchyOptions) -> [ViewNode] {
        let windows = allWindows()
        return windows.enumerated().map { idx, window in
            captureView(window, window: window, options: options, path: "win\(idx)", depth: 0, suppressSwiftUI: false)
        }
    }

    private func allWindows() -> [UIWindow] {
        var windows: [UIWindow] = []
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }
        for scene in scenes {
            windows.append(contentsOf: scene.windows)
        }
        if windows.isEmpty {
            // Fallback for older single-window setups.
            windows = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
        }
        return windows
            .filter { !$0.isHidden && $0.bounds.width > 0 }
            .sorted { $0.windowLevel.rawValue < $1.windowLevel.rawValue }
    }

    private func captureView(_ view: UIView, window: UIWindow, options: HierarchyOptions,
                             path: String, depth: Int, suppressSwiftUI: Bool) -> ViewNode {
        let id = register(view)
        let absFrame = view is UIWindow
            ? CGRect(origin: .zero, size: view.bounds.size)
            : view.convert(view.bounds, to: window)

        var flags: ViewFlags = []
        if view.isHidden { flags.insert(.hidden) }
        if view.clipsToBounds { flags.insert(.clipsToBounds) }
        if view.isUserInteractionEnabled { flags.insert(.userInteraction) }
        if view.bounds.isEmpty { flags.insert(.zeroSize) }
        if isSystemView(view) { flags.insert(.systemView) }

        let className = NSStringFromClass(type(of: view))
        let isHosting = className.contains("HostingView") || className.contains("HostingScrollView")

        var children: [ViewNode] = []
        var suppressChildren = suppressSwiftUI
        if isHosting, !suppressSwiftUI, options.includeSwiftUI, let rootView = swiftUIRootView(of: view) {
            flags.insert(.hostsSwiftUI)
            if let node = SwiftUIReflector().reflect(
                rootValue: rootView,
                pathPrefix: "\(path)/sui",
                anchorFrame: Rect(x: 0, y: 0, width: Double(absFrame.width), height: Double(absFrame.height))) {
                children.append(node)
                suppressChildren = true
            }
        }

        if depth == 0 || options.maxDepth == 0 || depth < options.maxDepth {
            for sub in view.subviews {
                if options.hideSystemViews, isSystemView(sub) { continue }
                children.append(captureView(sub, window: window, options: options,
                                            path: "\(path)/\(children.count)", depth: depth + 1,
                                            suppressSwiftUI: suppressChildren))
            }
        }

        // Standalone CALayers. Always included for SwiftUI hosting views (so the
        // canvas gets real rendered geometry); otherwise gated by the option.
        if options.includeLayers || isHosting {
            children.append(contentsOf: captureLayerChildren(
                of: view.layer,
                absoluteOrigin: Point(x: Double(absFrame.minX), y: Double(absFrame.minY)),
                options: options, path: "\(path)/layer", depth: depth))
        }

        var node = ViewNode(
            id: id,
            kind: view is UIWindow ? .window : .uiView,
            className: className,
            displayName: ValueDescriber.baseName(className),
            label: view.accessibilityIdentifier ?? view.accessibilityLabel,
            frame: rect(absFrame),
            bounds: rect(view.bounds),
            opacity: Double(view.alpha),
            flags: flags,
            zIndex: Double(view.layer.zPosition),
            transform: transform(view.layer),
            sections: uiViewSections(view),
            snapshotID: options.requestSnapshots && !view.bounds.isEmpty ? id : nil,
            children: children)
        if view.alpha < 1 { node.opacity = Double(view.alpha) }
        return node
    }

    private func swiftUIRootView(of view: UIView) -> Any? {
        SwiftUIReflector.findRootView(in: view)
    }

    private func isSystemView(_ view: UIView) -> Bool {
        let name = NSStringFromClass(type(of: view))
        return name.hasPrefix("_") || name.hasPrefix("UIInputSetHostView")
            || name.contains("Keyboard") || name.hasPrefix("UIDropShadowView")
    }

    // MARK: Properties

    private func uiViewSections(_ view: UIView) -> [AttributeSection] {
        var layout: [Attribute] = [
            Attribute(title: "frame", value: .rect(rect(view.frame)), editable: true, keyPath: "frame"),
            Attribute(title: "bounds", value: .rect(rect(view.bounds))),
            Attribute(title: "center", value: .point(Point(x: Double(view.center.x), y: Double(view.center.y)))),
        ]
        if !view.layer.transform.isIdentityApprox {
            layout.append(Attribute(title: "transform3D", value: .string("non-identity")))
        }

        var appearance: [Attribute] = [
            Attribute(title: "alpha", value: .number(Double(view.alpha)), editable: true, keyPath: "alpha"),
            Attribute(title: "hidden", value: .bool(view.isHidden), editable: true, keyPath: "hidden"),
            Attribute(title: "opaque", value: .bool(view.isOpaque)),
            Attribute(title: "clipsToBounds", value: .bool(view.clipsToBounds)),
        ]
        if let bg = view.backgroundColor, let c = ValueDescriber.colorValue(bg) {
            appearance.append(Attribute(title: "backgroundColor", value: .color(c), editable: true, keyPath: "backgroundColor"))
        }
        if let tint = ValueDescriber.colorValue(view.tintColor as Any) {
            appearance.append(Attribute(title: "tintColor", value: .color(tint)))
        }

        var layer: [Attribute] = [
            Attribute(title: "cornerRadius", value: .number(Double(view.layer.cornerRadius)), editable: true, keyPath: "cornerRadius"),
            Attribute(title: "borderWidth", value: .number(Double(view.layer.borderWidth))),
            Attribute(title: "masksToBounds", value: .bool(view.layer.masksToBounds)),
            Attribute(title: "zPosition", value: .number(Double(view.layer.zPosition))),
        ]
        if let bc = view.layer.borderColor, let c = ValueDescriber.colorValue(bc) {
            layer.append(Attribute(title: "borderColor", value: .color(c)))
        }
        if view.layer.shadowOpacity > 0 {
            layer.append(Attribute(title: "shadowOpacity", value: .number(Double(view.layer.shadowOpacity))))
            layer.append(Attribute(title: "shadowRadius", value: .number(Double(view.layer.shadowRadius))))
        }

        let interaction: [Attribute] = [
            Attribute(title: "userInteractionEnabled", value: .bool(view.isUserInteractionEnabled)),
            Attribute(title: "tag", value: .integer(view.tag)),
        ]

        var accessibility: [Attribute] = []
        if let id = view.accessibilityIdentifier { accessibility.append(Attribute(title: "identifier", value: .string(id))) }
        if let label = view.accessibilityLabel { accessibility.append(Attribute(title: "label", value: .string(label))) }

        return [AttributeSection].build([
            ("Layout", layout),
            ("Appearance", appearance),
            ("Layer", layer),
            ("Interaction", interaction),
            ("Accessibility", accessibility),
            ("Class", typeSpecificAttributes(view)),
        ])
    }

    private func typeSpecificAttributes(_ view: UIView) -> [Attribute] {
        switch view {
        case let label as UILabel:
            var a: [Attribute] = [Attribute(title: "text", value: .string(label.text ?? ""), editable: true, keyPath: "text")]
            a.append(Attribute(title: "numberOfLines", value: .integer(label.numberOfLines)))
            a.append(Attribute(title: "fontSize", value: .number(Double(label.font.pointSize))))
            if let c = ValueDescriber.colorValue(label.textColor as Any) {
                a.append(Attribute(title: "textColor", value: .color(c)))
            }
            return a
        case let tf as UITextField:
            return [
                Attribute(title: "text", value: .string(tf.text ?? ""), editable: true, keyPath: "text"),
                Attribute(title: "placeholder", value: .string(tf.placeholder ?? "")),
            ]
        case let button as UIButton:
            return [Attribute(title: "title", value: .string(button.title(for: .normal) ?? ""))]
        case let imageView as UIImageView:
            if let img = imageView.image {
                return [Attribute(title: "image", value: .image(width: Int(img.size.width), height: Int(img.size.height)))]
            }
            return []
        case let scroll as UIScrollView:
            return [
                Attribute(title: "contentSize", value: .size(Size(width: Double(scroll.contentSize.width), height: Double(scroll.contentSize.height)))),
                Attribute(title: "contentOffset", value: .point(Point(x: Double(scroll.contentOffset.x), y: Double(scroll.contentOffset.y)))),
            ]
        default:
            return []
        }
    }

    // MARK: Snapshot

    func renderSnapshot(object: AnyObject, nodeID: String, scale: Double) -> SnapshotImage? {
        guard let view = object as? UIView, !view.bounds.isEmpty else { return nil }
        let renderScale = max(1.0, min(scale, Double(UIScreen.main.scale)))
        let format = UIGraphicsImageRendererFormat()
        format.scale = CGFloat(renderScale)
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(bounds: view.bounds, format: format)
        let image = renderer.image { ctx in
            view.layer.render(in: ctx.cgContext)
        }
        guard let data = image.pngData() else { return nil }
        return SnapshotImage(nodeID: nodeID, format: .png, scale: renderScale,
                             pixelSize: Size(width: Double(view.bounds.width * CGFloat(renderScale)),
                                             height: Double(view.bounds.height * CGFloat(renderScale))),
                             data: data)
    }

    // MARK: Live edit

    func setAttribute(on object: AnyObject, keyPath: String, value: AttributeValue) -> (Bool, String?) {
        guard let view = object as? UIView else { return (false, "not a UIView") }
        let value = value.coercingIntegerToNumber
        switch (keyPath, value) {
        case ("alpha", .number(let n)):
            view.alpha = CGFloat(n); return (true, nil)
        case ("hidden", .bool(let b)):
            view.isHidden = b; return (true, nil)
        case ("cornerRadius", .number(let n)):
            view.layer.cornerRadius = CGFloat(n); return (true, nil)
        case ("backgroundColor", .color(let c)):
            view.backgroundColor = UIColor(red: CGFloat(c.red), green: CGFloat(c.green), blue: CGFloat(c.blue), alpha: CGFloat(c.alpha))
            return (true, nil)
        case ("text", .string(let s)):
            if let label = view as? UILabel { label.text = s; return (true, nil) }
            if let tf = view as? UITextField { tf.text = s; return (true, nil) }
            return (false, "view has no text")
        default:
            return (false, "cannot set '\(keyPath)' here (unsupported key path or value type \(value.displayString))")
        }
    }

    // MARK: Highlight

    func highlight(nodeID: String?) -> Bool {
        clearHighlightOverlay()

        guard let nodeID, let object = object(for: nodeID) else { return nodeID == nil }
        if let layer = object as? CALayer { return highlightLayer(layer) }
        guard let view = object as? UIView else { return false }
        let overlay = UIView(frame: view.bounds)
        overlay.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.18)
        overlay.layer.borderColor = UIColor.systemBlue.cgColor
        overlay.layer.borderWidth = 1
        overlay.isUserInteractionEnabled = false
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(overlay)
        highlightRef = WeakObject(overlay)
        return true
    }
}

private extension CATransform3D {
    var isIdentityApprox: Bool { CATransform3DIsIdentity(self) }
}
#endif
